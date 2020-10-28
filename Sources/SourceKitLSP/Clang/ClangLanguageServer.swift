//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
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
///
/// In addition, it also intercepts notifications and replies from clangd in order to do things
/// like witholding diagnostics when fallback build settings are being used.
final class ClangLanguageServerShim: LanguageServer, ToolchainLanguageServer {

  /// The connection to the clangd LSP.
  let clangd: Connection

  /// Capabilities of the clangd LSP, if received.
  var capabilities: ServerCapabilities? = nil

  /// Path to the clang binary.
  let clang: AbsolutePath?

  /// Resolved build settings by file. Must be accessed with the `lock`.
  private var buildSettingsByFile: [DocumentURI: ClangBuildSettings] = [:]

  /// Lock protecting `buildSettingsByFile`.
  private var lock: Lock

  /// Creates a language server for the given client referencing the clang binary at the given path.
  public init(
    client: LocalConnection,
    clangd: Connection,
    clang: AbsolutePath?
  ) throws {
    self.clangd = clangd
    self.clang = clang
    self.lock = Lock()
    super.init(client: client)
  }

  public override func _registerBuiltinHandlers() {
    _register(ClangLanguageServerShim.publishDiagnostics)
  }

  public override func _handleUnknown<R>(_ req: Request<R>) {
    guard req.clientID != ObjectIdentifier(clangd) else {
      forwardRequest(req, to: client)
      return
    }
    super._handleUnknown(req)
  }

  public override func _handleUnknown<N>(_ note: Notification<N>) {
    if note.clientID == ObjectIdentifier(clangd) {
      client.send(note.params)
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

// MARK: - LanguageServer

extension ClangLanguageServerShim {

  /// Intercept clangd's `PublishDiagnosticsNotification` to withold it if we're using fallback
  /// build settings.
  func publishDiagnostics(_ note: Notification<PublishDiagnosticsNotification>) {
    let params = note.params
    let buildSettings = self.lock.withLock {
      return self.buildSettingsByFile[params.uri]
    }
    let isFallback = buildSettings?.isFallback ?? true
    guard isFallback else {
      client.send(note.params)
      return
    }
    // Fallback: send empty publish notification instead.
    client.send(PublishDiagnosticsNotification(
      uri: params.uri, version: params.version, diagnostics: []))
  }

}

// MARK: - ToolchainLanguageServer

extension ClangLanguageServerShim {

  func initializeSync(_ initialize: InitializeRequest) throws -> InitializeResult {
    let result = try clangd.sendSync(initialize)
    self.capabilities = result.capabilities
    return result
  }

  public func clientInitialized(_ initialized: InitializedNotification) {
    clangd.send(initialized)
  }

  public func shutdown() {
    _ = clangd.send(ShutdownRequest(), queue: queue) { [weak self] _ in
      self?.clangd.send(ExitNotification())
      if let localConnection = self?.client as? LocalConnection {
        localConnection.close()
      }
    }
  }

  // MARK: - Text synchronization

  public func openDocument(_ note: DidOpenTextDocumentNotification) {
    clangd.send(note)
  }

  public func closeDocument(_ note: DidCloseTextDocumentNotification) {
    clangd.send(note)

    // Don't clear cached build settings since we've already informed clangd of the settings for the
    // file; if we clear the build settings here we should give clangd dummy build settings to make
    // sure we're in sync.
  }

  public func changeDocument(_ note: DidChangeTextDocumentNotification) {
    clangd.send(note)
  }

  public func willSaveDocument(_ note: WillSaveTextDocumentNotification) {

  }

  public func didSaveDocument(_ note: DidSaveTextDocumentNotification) {
    if capabilities?.textDocumentSync?.save?.isSupported == true {
      clangd.send(note)
    }
  }

  // MARK: - Build System Integration

  public func documentUpdatedBuildSettings(_ uri: DocumentURI, change: FileBuildSettingsChange) {
    guard let url = uri.fileURL else {
      // FIXME: The clang workspace can probably be reworked to support non-file URIs.
      log("Received updated build settings for non-file URI '\(uri)'. Ignoring the update.")
      return
    }
    let clangBuildSettings = ClangBuildSettings(change: change, clang: self.clang)
    logAsync(level: clangBuildSettings == nil ? .warning : .debug) { _ in
      let settingsStr = clangBuildSettings == nil ? "nil" : clangBuildSettings!.compilerArgs.description
      return "settings for \(uri): \(settingsStr)"
    }

    let changed = lock.withLock { () -> Bool in
      let prevBuildSettings = self.buildSettingsByFile[uri]
      guard clangBuildSettings != prevBuildSettings else { return false }
      self.buildSettingsByFile[uri] = clangBuildSettings
      return true
    }
    guard changed else { return }

    // The compile command changed, send over the new one.
    // FIXME: what should we do if we no longer have valid build settings?
    if let compileCommand = clangBuildSettings?.compileCommand {
      clangd.send(DidChangeConfigurationNotification(settings: .clangd(
        ClangWorkspaceSettings(
          compilationDatabaseChanges: [url.path: compileCommand]))))
    }
  }

  public func documentDependenciesUpdated(_ uri: DocumentURI) {
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
    if capabilities?.colorProvider?.isSupported == true {
      forwardRequest(req, to: clangd)
    } else {
      req.reply(.success([]))
    }
  }

  func colorPresentation(_ req: Request<ColorPresentationRequest>) {
    if capabilities?.colorProvider?.isSupported == true {
      forwardRequest(req, to: clangd)
    } else {
      req.reply(.success([]))
    }
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
  clangdOptions: [String]
) throws -> ToolchainLanguageServer {
  guard let clangd = toolchain.clangd else {
    preconditionFailure("missing clang from toolchain \(toolchain.identifier)")
  }

  let usToClangd: Pipe = Pipe()
  let clangdToUs: Pipe = Pipe()

  let connection = JSONRPCConnection(
    protocol: MessageRegistry.lspProtocol,
    inFD: clangdToUs.fileHandleForReading,
    outFD: usToClangd.fileHandleForWriting
  )

  let connectionToClient = LocalConnection()

  let shim = try ClangLanguageServerShim(
    client: connectionToClient,
    clangd: connection,
    clang: toolchain.clang)

  connectionToClient.start(handler: client)
  connection.start(receiveHandler: shim) {
    // FIXME: keep the pipes alive until we close the connection. This
    // should be fixed systemically.
    withExtendedLifetime((usToClangd, clangdToUs)) {}
  }

  let process = Foundation.Process()

  if #available(OSX 10.13, *) {
    process.executableURL = clangd.asURL
  } else {
    process.launchPath = clangd.pathString
  }

  process.arguments = [
    "-compile_args_from=lsp",   // Provide compiler args programmatically.
    "-background-index=false",  // Disable clangd indexing, we use the build
    "-index=false"             // system index store instead.
  ] + clangdOptions

  process.standardOutput = clangdToUs
  process.standardInput = usToClangd
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

/// Clang build settings derived from a `FileBuildSettingsChange`.
private struct ClangBuildSettings: Equatable {
  /// The compiler arguments, including the program name, argv[0].
  public let compilerArgs: [String]

  /// The working directory for the invocation.
  public let workingDirectory: String

  /// Whether the compiler arguments are considered fallback - we withhold diagnostics for
  /// fallback arguments and represent the file state differently.
  public let isFallback: Bool

  public init(_ settings: FileBuildSettings, clang: AbsolutePath?, isFallback: Bool = false) {
    var arguments = [clang?.pathString ?? "clang"] + settings.compilerArguments
    if arguments.contains("-fmodules") {
      // Clangd is not built with support for the 'obj' format.
      arguments.append(contentsOf: [
        "-Xclang", "-fmodule-format=raw"
      ])
    }
    if let workingDirectory = settings.workingDirectory {
      // FIXME: this is a workaround for clangd not respecting the compilation
      // database's "directory" field for relative -fmodules-cache-path.
      // rdar://63984913
      arguments.append(contentsOf: [
        "-working-directory", workingDirectory
      ])
    }

    self.compilerArgs = arguments
    self.workingDirectory = settings.workingDirectory ?? ""
    self.isFallback = isFallback
  }

  public init?(change: FileBuildSettingsChange, clang: AbsolutePath?) {
    switch change {
    case .fallback(let settings): self.init(settings, clang: clang, isFallback: true)
    case .modified(let settings): self.init(settings, clang: clang, isFallback: false)
    case .removedOrUnavailable: return nil
    }
  }

  public var compileCommand: ClangCompileCommand {
    return ClangCompileCommand(
        compilationCommand: self.compilerArgs, workingDirectory: self.workingDirectory)
  }
}
