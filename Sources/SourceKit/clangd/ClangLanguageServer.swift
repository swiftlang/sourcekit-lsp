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

  /// The server's request queue, used to serialize requests and responses to `clangd`.
  public let queue: DispatchQueue = DispatchQueue(label: "clangd-language-server-queue", qos: .userInitiated)

  let clangd: Connection

  var capabilities: ServerCapabilities? = nil

  let buildSystem: BuildSystem

  let clang: AbsolutePath?

  /// Creates a language server for the given client using the sourcekitd dylib at the specified path.
  public init(client: Connection, clangd: Connection, buildSystem: BuildSystem,
              clang: AbsolutePath?) throws {
    self.clangd = clangd
    self.buildSystem = buildSystem
    self.clang = clang
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

  func initializeSync(_ initialize: InitializeRequest) throws -> InitializeResult {
    let result = try clangd.sendSync(initialize)
    self.capabilities = result.capabilities
    return result
  }

  public func clientInitialized(_ initialized: InitializedNotification) {
    clangd.send(initialized)
  }

  // MARK: - Text synchronization

  public func openDocument(_ note: DidOpenTextDocumentNotification) {
    let textDocument = note.textDocument
    documentUpdatedBuildSettings(textDocument.uri, language: textDocument.language)
    clangd.send(note)
  }

  public func closeDocument(_ note: DidCloseTextDocumentNotification) {
    clangd.send(note)
  }

  public func changeDocument(_ note: DidChangeTextDocumentNotification) {
    clangd.send(note)
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
      clangd.send(DidChangeConfigurationNotification(settings: .clangd(
        ClangWorkspaceSettings(
          compilationDatabaseChanges: [url.path: ClangCompileCommand(settings, clang: clang)]))))
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
    clangd.send(note)
  }

  // MARK: - Text Document


  /// Returns true if the `ToolchainLanguageServer` will take ownership of the request.
  public func definition(_ req: Request<DefinitionRequest>) -> Bool {
    // We handle it to provide jump-to-header support for #import/#include.
    forwardRequest(req, to: clangd)
    return true
  }

  func completion(_ req: Request<CompletionRequest>) {
    forwardRequest(req, to: clangd)
  }

  func hover(_ req: Request<HoverRequest>) {
    forwardRequest(req, to: clangd)
  }

  func symbolInfo(_ req: Request<SymbolInfoRequest>) {
    forwardRequest(req, to: clangd)
  }

  func documentSymbolHighlight(_ req: Request<DocumentHighlightRequest>) {
    forwardRequest(req, to: clangd)
  }

  func documentSymbol(_ req: Request<DocumentSymbolRequest>) {
    forwardRequest(req, to: clangd)
  }

  func documentColor(_ req: Request<DocumentColorRequest>) {
    forwardRequest(req, to: clangd)
  }

  func colorPresentation(_ req: Request<ColorPresentationRequest>) {
    forwardRequest(req, to: clangd)
  }

  func codeAction(_ req: Request<CodeActionRequest>) {
    forwardRequest(req, to: clangd)
  }

  func foldingRange(_ req: Request<FoldingRangeRequest>) {
    if capabilities?.foldingRangeProvider?.isSupported == true {
      forwardRequest(req, to: clangd)
    } else {
      req.reply(.success(nil))
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
  clangdOptions: [String]
) throws -> ToolchainLanguageServer {
  guard let clangd = toolchain.clangd else {
    preconditionFailure("missing clang from toolchain \(toolchain.identifier)")
  }

  let clientToServer: Pipe = Pipe()
  let serverToClient: Pipe = Pipe()

  let connection = JSONRPCConnection(
    protocol: MessageRegistry.lspProtocol,
    inFD: serverToClient.fileHandleForReading.fileDescriptor,
    outFD: clientToServer.fileHandleForWriting.fileDescriptor
  )

  let connectionToClient = LocalConnection()

  let shim = try ClangLanguageServerShim(
    client: connectionToClient,
    clangd: connection,
    buildSystem: buildSettings ?? BuildSystemList(),
    clang: toolchain.clang)

  connectionToClient.start(handler: client)
  connection.start(receiveHandler: client)

  let process = Foundation.Process()

  if #available(OSX 10.13, *) {
    process.executableURL = clangd.asURL
  } else {
    process.launchPath = clangd.pathString
  }

  process.arguments = [
    "-compile_args_from=lsp",   // Provide compiler args programmatically.
    "-background-index=false",  // Disable clangd indexing, we use the build
    "-index=false",             // system index store instead.
  ] + clangdOptions

  process.standardOutput = serverToClient
  process.standardInput = clientToServer
  process.terminationHandler = { process in
    log("clangd exited: \(process.terminationReason) \(process.terminationStatus)")
    connection.close()
  }

  if #available(OSX 10.13, *) {
    try process.run()
  } else {
    process.launch()
  }

  return shim
}

extension ClangCompileCommand {
  init(_ settings: FileBuildSettings, clang: AbsolutePath?) {
    // Clang expects the first argument to be the program name, like argv.
    self.init(
      compilationCommand: [clang?.pathString ?? "clang"] + settings.compilerArguments,
      workingDirectory: settings.workingDirectory ?? "")
  }
}
