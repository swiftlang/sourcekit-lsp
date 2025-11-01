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

import BuildServerIntegration
import Foundation
import IndexStoreDB
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import LanguageServerProtocolJSONRPC
import SKLogging
package import SKOptions
package import SourceKitLSP
package import SwiftExtensions
package import SwiftSyntax
import TSCExtensions
package import ToolchainRegistry

#if os(Windows)
import WinSDK
#endif

/// A thin wrapper over a connection to a clangd server providing build setting handling.
///
/// In addition, it also intercepts notifications and replies from clangd in order to do things
/// like withholding diagnostics when fallback build settings are being used.
///
/// ``ClangLanguageServerShim`` conforms to ``MessageHandler`` to receive
/// requests and notifications **from** clangd, not from the editor, and it will
/// forward these requests and notifications to the editor.
package actor ClangLanguageService: LanguageService, MessageHandler {
  /// The queue on which all messages that originate from clangd are handled.
  ///
  /// These are requests and notifications sent *from* clangd, not replies from
  /// clangd.
  ///
  /// Since we are blindly forwarding requests from clangd to the editor, we
  /// cannot allow concurrent requests. This should be fine since the number of
  /// requests and notifications sent from clangd to the client is quite small.
  package let clangdMessageHandlingQueue = AsyncQueue<Serial>()

  /// The ``SourceKitLSPServer`` instance that created this `ClangLanguageService`.
  ///
  /// Used to send requests and notifications to the editor.
  private weak var sourceKitLSPServer: SourceKitLSPServer?

  /// The connection to the clangd LSP. `nil` until `startClangdProcesss` has been called.
  var clangd: Connection!

  /// Capabilities of the clangd LSP, if received.
  var capabilities: ServerCapabilities? = nil

  /// Path to the clang binary.
  let clangPath: URL?

  /// Path to the `clangd` binary.
  let clangdPath: URL

  let options: SourceKitLSPOptions

  /// The current state of the `clangd` language server.
  /// Changing the property automatically notified the state change handlers.
  private var state: LanguageServerState {
    didSet {
      for handler in stateChangeHandlers {
        handler(oldValue, state)
      }
    }
  }

  private var stateChangeHandlers: [(_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void] = []

  /// The date at which `clangd` was last restarted.
  /// Used to delay restarting in case of a crash loop.
  private var lastClangdRestart: Date?

  /// Whether or not a restart of `clangd` has been scheduled.
  /// Used to make sure we are not restarting `clangd` twice.
  private var clangRestartScheduled = false

  /// The `InitializeRequest` with which `clangd` was originally initialized.
  /// Stored so we can replay the initialization when clangd crashes.
  private var initializeRequest: InitializeRequest?

  /// The workspace this `ClangLanguageServer` was opened for.
  ///
  /// `clangd` doesn't have support for multi-root workspaces, so we need to start a separate `clangd` instance for every workspace root.
  private let workspace: WeakWorkspace

  /// The documents that have been opened and which language they have been
  /// opened with.
  private var openDocuments: [DocumentURI: LanguageServerProtocol.Language] = [:]

  /// Type to map `clangd`'s semantic token legend to SourceKit-LSP's.
  private var semanticTokensTranslator: SemanticTokensLegendTranslator? = nil

  /// While `clangd` is running, its `Process` object.
  private var clangdProcess: Process?

  package static var builtInCommands: [String] { [] }

  /// Creates a language server for the given client referencing the clang binary specified in `toolchain`.
  /// Returns `nil` if `clangd` can't be found.
  package init(
    sourceKitLSPServer: SourceKitLSPServer,
    toolchain: Toolchain,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    workspace: Workspace
  ) async throws {
    guard let clangdPath = toolchain.clangd else {
      throw ResponseError.unknown(
        "Cannot create SwiftLanguage service because \(toolchain.identifier) does not contain clangd"
      )
    }
    self.clangPath = toolchain.clang
    self.clangdPath = clangdPath
    self.options = options
    self.workspace = WeakWorkspace(workspace)
    self.state = .connected
    self.sourceKitLSPServer = sourceKitLSPServer
    try startClangdProcess()
  }

  private func buildSettings(for document: DocumentURI, fallbackAfterTimeout: Bool) async -> ClangBuildSettings? {
    guard let workspace = workspace.value, let language = openDocuments[document] else {
      return nil
    }
    guard
      let settings = await workspace.buildServerManager.buildSettingsInferredFromMainFile(
        for: document,
        language: language,
        fallbackAfterTimeout: fallbackAfterTimeout
      )
    else {
      return nil
    }
    return ClangBuildSettings(settings, clangPath: clangPath)
  }

  package nonisolated func canHandle(workspace: Workspace, toolchain: Toolchain) -> Bool {
    // We launch different clangd instance for each workspace because clangd doesn't have multi-root workspace support.
    return workspace === self.workspace.value && self.clangdPath == toolchain.clangd
  }

  package func addStateChangeHandler(handler: @escaping (LanguageServerState, LanguageServerState) -> Void) {
    self.stateChangeHandlers.append(handler)
  }

  /// Called after the `clangd` process exits.
  ///
  /// Restarts `clangd` if it has crashed.
  ///
  /// - Parameter terminationStatus: The exit code of `clangd`.
  private func handleClangdTermination(terminationReason: JSONRPCConnection.TerminationReason) {
    self.clangdProcess = nil
    if terminationReason != .exited(exitCode: 0) {
      self.state = .connectionInterrupted
      logger.info("clangd crashed. Restarting it.")
      self.restartClangd()
    }
  }

  /// Start the `clangd` process, either on creation of the `ClangLanguageService` or after `clangd` has crashed.
  private func startClangdProcess() throws {
    // Since we are starting a new clangd process, reset the list of open document
    openDocuments = [:]

    let (connectionToClangd, process) = try JSONRPCConnection.start(
      executable: clangdPath,
      arguments: [
        "-compile_args_from=lsp",  // Provide compiler args programmatically.
        "-background-index=false",  // Disable clangd indexing, we use the build
        "-index=false",  // system index store instead.
      ] + (options.clangdOptions ?? []),
      name: "clangd",
      protocol: MessageRegistry.lspProtocol,
      stderrLoggingCategory: "clangd-stderr",
      client: self,
      terminationHandler: { [weak self] terminationReason in
        guard let self = self else { return }
        Task {
          await self.handleClangdTermination(terminationReason: terminationReason)
        }

      }
    )
    self.clangd = connectionToClangd

    self.clangdProcess = process
  }

  /// Restart `clangd` after it has crashed.
  /// Delays restarting of `clangd` in case there is a crash loop.
  private func restartClangd() {
    precondition(self.state == .connectionInterrupted)

    precondition(self.clangRestartScheduled == false)
    self.clangRestartScheduled = true

    guard let initializeRequest = self.initializeRequest else {
      logger.error("clangd crashed before it was sent an InitializeRequest.")
      return
    }

    let restartDelay: Duration
    if let lastClangdRestart = self.lastClangdRestart, Date().timeIntervalSince(lastClangdRestart) < 30 {
      logger.log("clangd has already been restarted in the last 30 seconds. Delaying another restart by 10 seconds.")
      restartDelay = .seconds(10)
    } else {
      restartDelay = .zero
    }
    self.lastClangdRestart = Date()

    Task {
      try await Task.sleep(for: restartDelay)
      self.clangRestartScheduled = false
      do {
        try self.startClangdProcess()
        // We assume that clangd will return the same capabilities after restarting.
        // Theoretically they could have changed and we would need to inform SourceKitLSPServer about them.
        // But since SourceKitLSPServer more or less ignores them right now anyway, this should be fine for now.
        _ = try await self.initialize(initializeRequest)
        await self.clientInitialized(InitializedNotification())
        if let sourceKitLSPServer {
          await sourceKitLSPServer.reopenDocuments(for: self)
        } else {
          logger.fault("Cannot reopen documents because SourceKitLSPServer is no longer alive")
        }
        self.state = .connected
      } catch {
        logger.fault("Failed to restart clangd after a crash.")
      }
    }
  }

  /// Handler for notifications received **from** clangd, ie. **clangd** is
  /// sending a notification that's intended for the editor.
  ///
  /// We should either handle it ourselves or forward it to the editor.
  package nonisolated func handle(_ params: some NotificationType) {
    logger.info(
      """
      Received notification from clangd:
      \(params.forLogging)
      """
    )
    clangdMessageHandlingQueue.async {
      switch params {
      case let publishDiags as PublishDiagnosticsNotification:
        await self.publishDiagnostics(publishDiags)
      default:
        // We don't know how to handle any other notifications and ignore them.
        logger.error("Ignoring unknown notification \(type(of: params))")
        break
      }
    }
  }

  /// Handler for requests received **from** clangd, ie. **clangd** is
  /// sending a notification that's intended for the editor.
  ///
  /// We should either handle it ourselves or forward it to the client.
  package nonisolated func handle<R: RequestType>(
    _ params: R,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<R.Response>) -> Void
  ) {
    logger.info(
      """
      Received request from clangd:
      \(params.forLogging)
      """
    )
    clangdMessageHandlingQueue.async {
      guard let sourceKitLSPServer = await self.sourceKitLSPServer else {
        // `SourceKitLSPServer` has been destructed. We are tearing down the language
        // server. Nothing left to do.
        reply(.failure(.unknown("Connection to the editor closed")))
        return
      }

      do {
        let result = try await sourceKitLSPServer.sendRequestToClient(params)
        reply(.success(result))
      } catch {
        reply(.failure(ResponseError(error)))
      }
    }
  }

  /// Forward the given request to `clangd`.
  func forwardRequestToClangd<R: RequestType>(_ request: R) async throws -> R.Response {
    let timeoutHandle = TimeoutHandle()
    do {
      return try await withTimeout(options.semanticServiceRestartTimeoutOrDefault, handle: timeoutHandle) {
        await self.sourceKitLSPServer?.hooks.preForwardRequestToClangd?(request)
        return try await self.clangd.send(request)
      }
    } catch let error as TimeoutError where error.handle == timeoutHandle {
      logger.fault(
        "Did not receive reply from clangd after \(self.options.semanticServiceRestartTimeoutOrDefault, privacy: .public). Terminating and restarting clangd."
      )
      await self.crash()
      throw error
    }
  }

  package func canonicalDeclarationPosition(of position: Position, in uri: DocumentURI) async -> Position? {
    return nil
  }

  package func crash() async {
    clangdProcess?.terminateImmediately()
  }
}

// MARK: - LanguageServer

extension ClangLanguageService {

  /// Intercept clangd's `PublishDiagnosticsNotification` to withhold it if we're using fallback
  /// build settings.
  func publishDiagnostics(_ notification: PublishDiagnosticsNotification) async {
    // Technically, the publish diagnostics notification could still originate
    // from when we opened the file with fallback build settings and we could
    // have received real build settings since, which haven't been acknowledged
    // by clangd yet.
    //
    // Since there is no way to tell which build settings clangd used to generate
    // the diagnostics, there's no good way to resolve this race. For now, this
    // should be good enough since the time in which the race may occur is pretty
    // short and we expect clangd to send us new diagnostics with the updated
    // non-fallback settings very shortly after, which will override the
    // incorrect result, making it very temporary.
    // TODO: We want to know the build settings that are currently transmitted to clangd, not whichever ones we would
    // get next. (https://github.com/swiftlang/sourcekit-lsp/issues/1761)
    let buildSettings = await self.buildSettings(for: notification.uri, fallbackAfterTimeout: true)
    guard let sourceKitLSPServer else {
      logger.fault("Cannot publish diagnostics because SourceKitLSPServer has been destroyed")
      return
    }
    if buildSettings?.isFallback ?? true {
      // Fallback: send empty publish notification instead.
      sourceKitLSPServer.sendNotificationToClient(
        PublishDiagnosticsNotification(
          uri: notification.uri,
          version: notification.version,
          diagnostics: []
        )
      )
    } else {
      sourceKitLSPServer.sendNotificationToClient(notification)
    }
  }

}

// MARK: - LanguageService

extension ClangLanguageService {

  package func initialize(_ initialize: InitializeRequest) async throws -> InitializeResult {
    // Store the initialize request so we can replay it in case clangd crashes
    self.initializeRequest = initialize

    let result = try await clangd.send(initialize)
    self.capabilities = result.capabilities
    if let legend = result.capabilities.semanticTokensProvider?.legend {
      self.semanticTokensTranslator = SemanticTokensLegendTranslator(
        clangdLegend: legend,
        sourceKitLSPLegend: SemanticTokensLegend.sourceKitLSPLegend
      )
    }
    return result
  }

  package func clientInitialized(_ initialized: InitializedNotification) async {
    clangd.send(initialized)
  }

  package func shutdown() async {
    _ = await orLog("Shutting down clangd") {
      guard let clangd else { return }
      // Give clangd 2 seconds to shut down by itself. If it doesn't shut down within that time, terminate it.
      try await withTimeout(.seconds(2)) {
        _ = try await clangd.send(ShutdownRequest())
        clangd.send(ExitNotification())
      }
    }
    await orLog("Terminating clangd") {
      // Give clangd 1 second to exit after receiving the `exit` notification. If it doesn't exit within that time,
      // terminate it.
      try await clangdProcess?.terminateIfRunning(after: .seconds(1))
    }
  }

  // MARK: - Text synchronization

  package func openDocument(_ notification: DidOpenTextDocumentNotification, snapshot: DocumentSnapshot) async {
    openDocuments[notification.textDocument.uri] = notification.textDocument.language
    // Send clangd the build settings for the new file. We need to do this before
    // sending the open notification, so that the initial diagnostics already
    // have build settings.
    await documentUpdatedBuildSettings(notification.textDocument.uri)
    clangd.send(notification)
  }

  package func closeDocument(_ notification: DidCloseTextDocumentNotification) {
    openDocuments[notification.textDocument.uri] = nil
    clangd.send(notification)
  }

  package func reopenDocument(_ notification: ReopenTextDocumentNotification) {}

  package func changeDocument(
    _ notification: DidChangeTextDocumentNotification,
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot,
    edits: [SourceEdit]
  ) {
    clangd.send(notification)
  }

  package func willSaveDocument(_ notification: WillSaveTextDocumentNotification) async {

  }

  package func didSaveDocument(_ notification: DidSaveTextDocumentNotification) async {
    clangd.send(notification)
  }

  // MARK: - Build Server Integration

  package func documentUpdatedBuildSettings(_ uri: DocumentURI) async {
    guard let url = uri.fileURL else {
      logger.error("Received updated build settings for non-file URI '\(uri.forLogging)'. Ignoring the update.")
      return
    }
    let clangBuildSettings = await self.buildSettings(for: uri, fallbackAfterTimeout: false)

    // The compile command changed, send over the new one.
    if let compileCommand = clangBuildSettings?.compileCommand, let pathString = try? url.filePath {
      let notification = DidChangeConfigurationNotification(
        settings: .clangd(ClangWorkspaceSettings(compilationDatabaseChanges: [pathString: compileCommand]))
      )
      clangd.send(notification)
    } else {
      logger.error("No longer have build settings for \(url.description) but can't send null build settings to clangd")
    }
  }

  package func documentDependenciesUpdated(_ uris: Set<DocumentURI>) async {
    for uri in uris {
      // In order to tell clangd to reload an AST, we send it an empty `didChangeTextDocument`
      // with `forceRebuild` set in case any missing header files have been added.
      // This works well for us as the moment since clangd ignores the document version.
      let notification = DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 0),
        contentChanges: [],
        forceRebuild: true
      )
      clangd.send(notification)
    }
  }

  // MARK: - Text Document

  package func definition(_ req: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    // We handle it to provide jump-to-header support for #import/#include.
    return try await self.forwardRequestToClangd(req)
  }

  package func declaration(_ req: DeclarationRequest) async throws -> LocationsOrLocationLinksResponse? {
    return try await forwardRequestToClangd(req)
  }

  package func completion(_ req: CompletionRequest) async throws -> CompletionList {
    return try await forwardRequestToClangd(req)
  }

  package func completionItemResolve(_ req: CompletionItemResolveRequest) async throws -> CompletionItem {
    return try await forwardRequestToClangd(req)
  }

  package func signatureHelp(_ req: SignatureHelpRequest) async throws -> SignatureHelp? {
    return try await forwardRequestToClangd(req)
  }

  package func hover(_ req: HoverRequest) async throws -> HoverResponse? {
    return try await forwardRequestToClangd(req)
  }

  package func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    guard let language = openDocuments[req.textDocument.uri] else {
      throw ResponseError.requestFailed("Documentation preview is not available for clang files")
    }
    throw ResponseError.requestFailed("Documentation preview is not available for \(language.description) files")
  }

  package func symbolInfo(_ req: SymbolInfoRequest) async throws -> [SymbolDetails] {
    return try await forwardRequestToClangd(req)
  }

  package func documentSymbolHighlight(_ req: DocumentHighlightRequest) async throws -> [DocumentHighlight]? {
    return try await forwardRequestToClangd(req)
  }

  package func documentSymbol(_ req: DocumentSymbolRequest) async throws -> DocumentSymbolResponse? {
    return try await forwardRequestToClangd(req)
  }

  package func documentColor(_ req: DocumentColorRequest) async throws -> [ColorInformation] {
    guard self.capabilities?.colorProvider?.isSupported ?? false else {
      return []
    }
    return try await forwardRequestToClangd(req)
  }

  package func documentSemanticTokens(
    _ req: DocumentSemanticTokensRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    guard var response = try await forwardRequestToClangd(req) else {
      return nil
    }
    if let semanticTokensTranslator {
      response.data = semanticTokensTranslator.translate(response.data)
    }
    return response
  }

  package func documentSemanticTokensDelta(
    _ req: DocumentSemanticTokensDeltaRequest
  ) async throws -> DocumentSemanticTokensDeltaResponse? {
    guard var response = try await forwardRequestToClangd(req) else {
      return nil
    }
    if let semanticTokensTranslator {
      switch response {
      case .tokens(var tokens):
        tokens.data = semanticTokensTranslator.translate(tokens.data)
        response = .tokens(tokens)
      case .delta(var delta):
        delta.edits = delta.edits.map {
          var edit = $0
          if let data = edit.data {
            edit.data = semanticTokensTranslator.translate(data)
          }
          return edit
        }
        response = .delta(delta)
      }
    }
    return response
  }

  package func documentSemanticTokensRange(
    _ req: DocumentSemanticTokensRangeRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    guard var response = try await forwardRequestToClangd(req) else {
      return nil
    }
    if let semanticTokensTranslator {
      response.data = semanticTokensTranslator.translate(response.data)
    }
    return response
  }

  package func colorPresentation(_ req: ColorPresentationRequest) async throws -> [ColorPresentation] {
    guard self.capabilities?.colorProvider?.isSupported ?? false else {
      return []
    }
    return try await forwardRequestToClangd(req)
  }

  package func documentFormatting(_ req: DocumentFormattingRequest) async throws -> [TextEdit]? {
    return try await forwardRequestToClangd(req)
  }

  package func documentRangeFormatting(_ req: DocumentRangeFormattingRequest) async throws -> [TextEdit]? {
    return try await forwardRequestToClangd(req)
  }

  package func documentOnTypeFormatting(_ req: DocumentOnTypeFormattingRequest) async throws -> [TextEdit]? {
    return try await forwardRequestToClangd(req)
  }

  package func codeAction(_ req: CodeActionRequest) async throws -> CodeActionRequestResponse? {
    return try await forwardRequestToClangd(req)
  }

  package func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
    return try await forwardRequestToClangd(req)
  }

  package func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport {
    return try await forwardRequestToClangd(req)
  }

  package func codeLens(_ req: CodeLensRequest) async throws -> [CodeLens] {
    return try await forwardRequestToClangd(req) ?? []
  }

  package func foldingRange(_ req: FoldingRangeRequest) async throws -> [FoldingRange]? {
    guard self.capabilities?.foldingRangeProvider?.isSupported ?? false else {
      return nil
    }
    return try await forwardRequestToClangd(req)
  }

  package func indexedRename(_ request: IndexedRenameRequest) async throws -> WorkspaceEdit? {
    return try await forwardRequestToClangd(request)
  }

  // MARK: - Other

  package func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny? {
    return try await forwardRequestToClangd(req)
  }

  package func rename(_ renameRequest: RenameRequest) async throws -> (edits: WorkspaceEdit, usr: String?) {
    async let edits = forwardRequestToClangd(renameRequest)
    let symbolInfoRequest = SymbolInfoRequest(
      textDocument: renameRequest.textDocument,
      position: renameRequest.position
    )
    let symbolDetail = try await forwardRequestToClangd(symbolInfoRequest).only
    return (try await edits ?? WorkspaceEdit(), symbolDetail?.usr)
  }

  package func syntacticDocumentTests(
    for uri: DocumentURI,
    in workspace: Workspace
  ) async throws -> [AnnotatedTestItem]? {
    return nil
  }

  package static func syntacticTestItems(in uri: DocumentURI) async -> [AnnotatedTestItem] {
    return []
  }

  package func syntacticDocumentPlaygrounds(for uri: DocumentURI, in workspace: Workspace) async throws -> [PlaygroundItem] {
    return []
  }

  package func editsToRename(
    locations renameLocations: [RenameLocation],
    in snapshot: DocumentSnapshot,
    oldName oldCrossLanguageName: CrossLanguageName,
    newName newCrossLanguageName: CrossLanguageName
  ) async throws -> [TextEdit] {
    let positions = [
      snapshot.uri: renameLocations.compactMap { snapshot.position(of: $0) }
    ]
    guard
      let oldName = oldCrossLanguageName.clangName,
      let newName = newCrossLanguageName.clangName
    else {
      throw ResponseError.unknown(
        "Failed to rename \(snapshot.uri.forLogging) because the clang name for rename is unknown"
      )
    }
    let request = IndexedRenameRequest(
      textDocument: TextDocumentIdentifier(snapshot.uri),
      oldName: oldName,
      newName: newName,
      positions: positions
    )
    do {
      let edits = try await forwardRequestToClangd(request)
      return edits?.changes?[snapshot.uri] ?? []
    } catch {
      logger.error("Failed to get indexed rename edits: \(error.forLogging)")
      return []
    }
  }

  package func prepareRename(
    _ request: PrepareRenameRequest
  ) async throws -> (prepareRename: PrepareRenameResponse, usr: String?)? {
    guard let prepareRename = try await forwardRequestToClangd(request) else {
      return nil
    }
    let symbolInfo = try await forwardRequestToClangd(
      SymbolInfoRequest(textDocument: request.textDocument, position: request.position)
    )
    return (prepareRename, symbolInfo.only?.usr)
  }

  package func editsToRenameParametersInFunctionBody(
    snapshot: DocumentSnapshot,
    renameLocation: RenameLocation,
    newName: CrossLanguageName
  ) async -> [TextEdit] {
    // When renaming a clang function name, we don't need to rename any references to the arguments.
    return []
  }
}

/// Clang build settings derived from a `FileBuildSettingsChange`.
private struct ClangBuildSettings: Equatable {
  /// The compiler arguments, including the program name, argv[0].
  package let compilerArgs: [String]

  /// The working directory for the invocation.
  package let workingDirectory: String

  /// Whether the compiler arguments are considered fallback - we withhold diagnostics for
  /// fallback arguments and represent the file state differently.
  package let isFallback: Bool

  package init(_ settings: FileBuildSettings, clangPath: URL?) {
    var arguments = [(try? clangPath?.filePath) ?? "clang"] + settings.compilerArguments
    if arguments.contains("-fmodules") {
      // Clangd is not built with support for the 'obj' format.
      arguments.append(contentsOf: [
        "-Xclang", "-fmodule-format=raw",
      ])
    }
    if let workingDirectory = settings.workingDirectory {
      // TODO: This is a workaround for clangd not respecting the compilation
      // database's "directory" field for relative -fmodules-cache-path.
      // Remove once rdar://63984913 is fixed
      arguments.append(contentsOf: [
        "-working-directory", workingDirectory,
      ])
    }

    self.compilerArgs = arguments
    self.workingDirectory = settings.workingDirectory ?? ""
    self.isFallback = settings.isFallback
  }

  package var compileCommand: ClangCompileCommand {
    return ClangCompileCommand(
      compilationCommand: self.compilerArgs,
      workingDirectory: self.workingDirectory
    )
  }
}
