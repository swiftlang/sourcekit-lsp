//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import LSPLogging
import SKCore
import SKSupport
import TSCBasic

/// A thin wrapper over a connection to a clangd server providing build setting handling.
final class ClangLanguageServerShim: ToolchainLanguageServer {

  /// The server's request queue, used to protect shared access to mutable state and to serialize requests and responses to `clangd`.
  public let queue: DispatchQueue = DispatchQueue(label: "clangd-language-server-queue", qos: .userInitiated)

  /// The connection to `clangd`. `nil` before `initialize` has been called.
  private var clangd: Connection!

  private var capabilities: ServerCapabilities? = nil

  private let buildSystem: BuildSystem

  private let clangdPath: AbsolutePath

  private let clangdOptions: [String]

  private let client: MessageHandler

  private var state: LanguageServerState {
     didSet {
      if #available(OSX 10.12, *) {
        // `state` must only be set from `queue`.
        dispatchPrecondition(condition: .onQueue(queue))
      }
       for handler in stateChangeHandlers {
         handler(oldValue, state)
       }
     }
   }
  
  /// The date at which `clangd` was last restarted. Used to delay restarting in case of a crash loop.
  private var lastClangdRestart: Date?
  
  /// Whether or not a restart of `clangd` has been scheduled. Used to make sure we are not restarting `clangd` twice.
  private var clangRestartScheduled = false

  private var stateChangeHandlers: [(_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void] = []

  /// Ask the parent of this language server to re-open all documents in this language server.
  private let reopenDocuments: (ToolchainLanguageServer) -> Void

  /// The `InitializeRequest` with which `clangd` was originally initialized.
  /// Stored so we can replay the initialization when clangd crashes.
  private var initializeRequest: InitializeRequest?

  public init(client: MessageHandler,
              clangdPath: AbsolutePath,
              buildSettings: BuildSystem?,
              clangdOptions: [String],
              reopenDocuments: @escaping (ToolchainLanguageServer) -> Void
  ) throws {
    self.client = client
    self.buildSystem = buildSettings ?? BuildSystemList()
    self.clangdPath = clangdPath
    self.clangdOptions = clangdOptions
    self.state = .connected
    self.reopenDocuments = reopenDocuments
  }

  func startClangdProcess() throws {
    try queue.sync {
      let clientToServer: Pipe = Pipe()
      let serverToClient: Pipe = Pipe()
      
      let connection = JSONRPCConnection(
        protocol: MessageRegistry.lspProtocol,
        inFD: serverToClient.fileHandleForReading.fileDescriptor,
        outFD: clientToServer.fileHandleForWriting.fileDescriptor
      )
      
      self.clangd = connection
      
      connection.start(receiveHandler: client)
      
      let process = Foundation.Process()
      
      if #available(OSX 10.13, *) {
        process.executableURL = clangdPath.asURL
      } else {
        process.launchPath = clangdPath.pathString
      }
      
      process.arguments = [
        "-compile_args_from=lsp",   // Provide compiler args programmatically.
        "-background-index=false",  // Disable clangd indexing, we use the build
        "-index=false",             // system index store instead.
        ] + clangdOptions
      
      process.standardOutput = serverToClient
      process.standardInput = clientToServer
      process.terminationHandler = { [weak self] process in
        log("clangd exited: \(process.terminationReason) \(process.terminationStatus)")
        connection.close()
        if process.terminationStatus != 0 {
          if let self = self {
            self.queue.async {
              self.state = .connectionInterrupted
              self.restartClangd()
            }
          }
        }
      }
      
      if #available(OSX 10.13, *) {
        try process.run()
      } else {
        process.launch()
      }
    }
  }

  private func restartClangd() {
    queue.async {
      precondition(self.state == .connectionInterrupted)
      
      precondition(self.clangRestartScheduled == false)
      self.clangRestartScheduled = true
      
      guard let initializeRequest = self.initializeRequest else {
        log("clangd crashed before it was sent an InitializeRequest.", level: .error)
        return
      }
    
      let restartDelay: Int
      if let lastClangdRestart = self.lastClangdRestart, Date().timeIntervalSince(lastClangdRestart) < 30 {
        // We have crashed in the last 30 seconds. Delay any further restart by 10 seconds
        log("clangd crashed in the last 30 seconds. Delaying another restart by 10 seconds.", level: .info)
        restartDelay = 10
      } else {
        restartDelay = 0
      }
      self.lastClangdRestart = Date()
      
      DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(restartDelay)) {
        self.clangRestartScheduled = false
        do {
          try self.startClangdProcess()
          // FIXME: We assume that clangd will return the same capabilites after restarting.
          // Theoretically they could have changed and we would need to inform SourceKitServer about them.
          // But since SourceKitServer more or less ignores them right now anyway, this should be fine for now.
          _ = try self.initializeSync(initializeRequest)
          self.clientInitialized(InitializedNotification())
          self.reopenDocuments(self)
          self.queue.async {
            self.state = .connected
          }
        } catch {
          log("Failed to restart clangd after a crash.", level: .error)
        }
      }
    }
  }

  func addStateChangeHandler(handler: @escaping (LanguageServerState, LanguageServerState) -> Void) {
    queue.async {
      self.stateChangeHandlers.append(handler)
    }
  }


  /// Forwards a request to the given connection, taking care of replying to the original request
  /// and cancellation, while providing a callback with the response for additional processing.
  ///
  /// Immediately after `handler` returns, this passes the result to the original reply handler by
  /// calling `request.reply(result)`.
  ///
  /// The cancellation token from the original request is automatically linked to the forwarded
  /// request such that cancelling the original request will cancel the forwarded request.
  ///
  /// - Parameters:
  ///   - request: The request to forward.
  ///   - to: Where to forward the request (e.g. self.clangd).
  ///   - handler: An optional closure that will be called with the result of the request.
  func forwardRequest<R>(
    _ request: Request<R>,
    to: Connection,
    _ handler: ((LSPResult<R.Response>) -> Void)? = nil)
  {
    let id = to.send(request.params, queue: queue) { result in
      handler?(result)
      request.reply(result)
    }
    request.cancellationToken.addCancellationHandler {
      to.send(CancelRequestNotification(id: id))
    }
  }
}

// MARK: - Request and notification handling

extension ClangLanguageServerShim {
  
  /// Forward the given `notification` to `clangd` by asynchronously switching to `queue` for a thread-safe access to `clangd`.
  private func forwardNotificationToClangdOnQueue<Notification>(_ notification: Notification) where Notification: NotificationType {
    queue.async {
      self.clangd.send(notification)
    }
  }
  
  /// Forward the given `request` to `clangd` by asynchronously switching to `queue` for a thread-safe access to `clangd`.
  private func forwardRequestToClangdOnQueue<R>(_ request: Request<R>, _ handler: ((LSPResult<R.Response>) -> Void)? = nil) {
    queue.async {
      self.forwardRequest(request, to: self.clangd, handler)
    }
  }

  func initializeSync(_ initialize: InitializeRequest) throws -> InitializeResult {
    try queue.sync {
      self.initializeRequest = initialize
      let result = try clangd.sendSync(initialize)
      self.capabilities = result.capabilities
      return result
    }
  }

  public func clientInitialized(_ initialized: InitializedNotification) {
    forwardNotificationToClangdOnQueue(initialized)
  }

  // MARK: - Text synchronization

  public func openDocument(_ note: DidOpenTextDocumentNotification) {
    let textDocument = note.textDocument
    documentUpdatedBuildSettings(textDocument.uri, language: textDocument.language)
    forwardNotificationToClangdOnQueue(note)
  }

  public func closeDocument(_ note: DidCloseTextDocumentNotification) {
    forwardNotificationToClangdOnQueue(note)
  }

  public func changeDocument(_ note: DidChangeTextDocumentNotification) {
    forwardNotificationToClangdOnQueue(note)
  }

  public func willSaveDocument(_ note: WillSaveTextDocumentNotification) {

  }

  public func didSaveDocument(_ note: DidSaveTextDocumentNotification) {

  }

  // MARK: - Build System Integration

  public func documentUpdatedBuildSettings(_ uri: DocumentURI, language: Language) {
    guard let url = uri.fileURL else {
      // FIXME: The clang workspace can probably be reworked to support non-file URIs.
      log("Received updated build settings for non-file URI '\(uri)'. Ignoring the update.")
      return
    }
    let settings = buildSystem.settings(for: uri, language)

    logAsync(level: settings == nil ? .warning : .debug) { _ in
      let settingsStr = settings == nil ? "nil" : settings!.compilerArguments.description
      return "settings for \(uri): \(settingsStr)"
    }

    if let settings = settings {
      forwardNotificationToClangdOnQueue(DidChangeConfigurationNotification(settings: .clangd(
        ClangWorkspaceSettings(
          compilationDatabaseChanges: [url.path: ClangCompileCommand(settings, clang: clangdPath)]))))
    }
  }

  public func documentDependenciesUpdated(_ uri: DocumentURI, language: Language) {
    // In order to tell clangd to reload an AST, we send it an empty `didChangeTextDocument`
    // with `forceRebuild` set in case any missing header files have been added.
    // This works well for us as the moment since clangd ignores the document version.
    let note = DidChangeTextDocumentNotification(
      textDocument: VersionedTextDocumentIdentifier(uri, version: nil),
      contentChanges: [],
      forceRebuild: true)
    forwardNotificationToClangdOnQueue(note)
  }

  // MARK: - Text Document


  /// Returns true if the `ToolchainLanguageServer` will take ownership of the request.
  public func definition(_ req: Request<DefinitionRequest>) -> Bool {
    // We handle it to provide jump-to-header support for #import/#include.
    forwardRequest(req, to: clangd)
    return true
  }

  func completion(_ req: Request<CompletionRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func hover(_ req: Request<HoverRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func symbolInfo(_ req: Request<SymbolInfoRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func documentSymbolHighlight(_ req: Request<DocumentHighlightRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func documentSymbol(_ req: Request<DocumentSymbolRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func documentColor(_ req: Request<DocumentColorRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func colorPresentation(_ req: Request<ColorPresentationRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func codeAction(_ req: Request<CodeActionRequest>) {
    forwardRequestToClangdOnQueue(req)
  }

  func foldingRange(_ req: Request<FoldingRangeRequest>) {
    queue.async {
      if self.capabilities?.foldingRangeProvider?.isSupported == true {
        self.forwardRequest(req, to: self.clangd)
      } else {
        req.reply(.success(nil))
      }
    }
  }

  // MARK: - Other

  func executeCommand(_ req: Request<ExecuteCommandRequest>) {
    //TODO: Implement commands.
    return req.reply(nil)
  }
}

func makeJSONRPCClangServer(
  client: MessageHandler,
  toolchain: Toolchain,
  buildSettings: BuildSystem?,
  clangdOptions: [String],
  reopenDocuments: @escaping (ToolchainLanguageServer) -> Void
) throws -> ToolchainLanguageServer {
  guard let clangd = toolchain.clangd else {
    preconditionFailure("missing clang from toolchain \(toolchain.identifier)")
  }

  let server = try ClangLanguageServerShim(client: client, clangdPath: clangd, buildSettings: buildSettings, clangdOptions: clangdOptions, reopenDocuments: reopenDocuments)
  try server.startClangdProcess()
  return server
}

extension ClangCompileCommand {
  init(_ settings: FileBuildSettings, clang: AbsolutePath?) {
    // Clang expects the first argument to be the program name, like argv.
    self.init(
      compilationCommand: [clang?.pathString ?? "clang"] + settings.compilerArguments,
      workingDirectory: settings.workingDirectory ?? "")
  }
}
