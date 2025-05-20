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

import BuildServerProtocol
package import BuildSystemIntegration
import Csourcekitd
import Dispatch
import Foundation
import IndexStoreDB
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
package import SKOptions
import SKUtilities
import SemanticIndex
package import SourceKitD
import SwiftExtensions
import SwiftParser
import SwiftParserDiagnostics
package import SwiftSyntax
package import ToolchainRegistry

#if os(Windows)
import WinSDK
#endif

fileprivate extension Range {
  /// Checks if this range overlaps with the other range, counting an overlap with an empty range as a valid overlap.
  /// The standard library implementation makes `1..<3.overlaps(2..<2)` return false because the second range is empty and thus the overlap is also empty.
  /// This implementation over overlap considers such an inclusion of an empty range as a valid overlap.
  func overlapsIncludingEmptyRanges(other: Range<Bound>) -> Bool {
    switch (self.isEmpty, other.isEmpty) {
    case (true, true):
      return self.lowerBound == other.lowerBound
    case (true, false):
      return other.contains(self.lowerBound)
    case (false, true):
      return self.contains(other.lowerBound)
    case (false, false):
      return self.overlaps(other)
    }
  }
}

/// Explicitly excluded `DocumentURI` schemes.
fileprivate let excludedDocumentURISchemes: [String] = [
  "git",
  "hg",
]

/// Returns true if diagnostics should be emitted for the given document.
///
/// Some editors (like Visual Studio Code) use non-file URLs to manage source control diff bases
/// for the active document, which can lead to duplicate diagnostics in the Problems view.
/// As a workaround we explicitly exclude those URIs and don't emit diagnostics for them.
///
/// Additionally, as of Xcode 11.4, sourcekitd does not properly handle non-file URLs when
/// the `-working-directory` argument is passed since it incorrectly applies it to the input
/// argument but not the internal primary file, leading sourcekitd to believe that the input
/// file is missing.
fileprivate func diagnosticsEnabled(for document: DocumentURI) -> Bool {
  guard let scheme = document.scheme else { return true }
  return !excludedDocumentURISchemes.contains(scheme)
}

/// A swift compiler command derived from a `FileBuildSettingsChange`.
package struct SwiftCompileCommand: Sendable, Equatable, Hashable {

  /// The compiler arguments, including working directory. This is required since sourcekitd only
  /// accepts the working directory via the compiler arguments.
  package let compilerArgs: [String]

  /// Whether the compiler arguments are considered fallback - we withhold diagnostics for
  /// fallback arguments and represent the file state differently.
  package let isFallback: Bool

  package init(_ settings: FileBuildSettings) {
    let baseArgs = settings.compilerArguments
    // Add working directory arguments if needed.
    if let workingDirectory = settings.workingDirectory, !baseArgs.contains("-working-directory") {
      self.compilerArgs = baseArgs + ["-working-directory", workingDirectory]
    } else {
      self.compilerArgs = baseArgs
    }
    self.isFallback = settings.isFallback
  }
}

package actor SwiftLanguageService: LanguageService, Sendable {
  /// The ``SourceKitLSPServer`` instance that created this `SwiftLanguageService`.
  private(set) weak var sourceKitLSPServer: SourceKitLSPServer?

  private let sourcekitdPath: URL

  package let sourcekitd: SourceKitD

  /// Path to the swift-format executable if it exists in the toolchain.
  let swiftFormat: URL?

  /// Queue on which notifications from sourcekitd are handled to ensure we are
  /// handling them in-order.
  let sourcekitdNotificationHandlingQueue = AsyncQueue<Serial>()

  let capabilityRegistry: CapabilityRegistry

  let hooks: Hooks

  let options: SourceKitLSPOptions

  /// Directory where generated Swift interfaces will be stored.
  var generatedInterfacesPath: URL {
    options.generatedFilesAbsolutePath.appendingPathComponent("GeneratedInterfaces")
  }

  /// Directory where generated Macro expansions  will be stored.
  var generatedMacroExpansionsPath: URL {
    options.generatedFilesAbsolutePath.appendingPathComponent("GeneratedMacroExpansions")
  }

  /// For each edited document, the last task that was triggered to send a `PublishDiagnosticsNotification`.
  ///
  /// This is used to cancel previous publish diagnostics tasks if an edit is made to a document.
  ///
  /// - Note: We only clear entries from the dictionary when a document is closed. The task that the document maps to
  ///   might have finished. This isn't an issue since the tasks do not retain `self`.
  private var inFlightPublishDiagnosticsTasks: [DocumentURI: Task<Void, Never>] = [:]

  let syntaxTreeManager = SyntaxTreeManager()

  /// The `semanticIndexManager` of the workspace this language service was created for.
  private let semanticIndexManager: SemanticIndexManager?

  nonisolated var keys: sourcekitd_api_keys { return sourcekitd.keys }
  nonisolated var requests: sourcekitd_api_requests { return sourcekitd.requests }
  nonisolated var values: sourcekitd_api_values { return sourcekitd.values }

  /// - Important: Use `setState` to change the state, which notifies the state change handlers
  private var state: LanguageServerState

  private var stateChangeHandlers: [(_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void] = []

  private let diagnosticReportManager: DiagnosticReportManager

  /// - Note: Implicitly unwrapped optional so we can pass a reference of `self` to `MacroExpansionManager`.
  private(set) var macroExpansionManager: MacroExpansionManager! {
    willSet {
      // Must only be set once.
      precondition(macroExpansionManager == nil)
      precondition(newValue != nil)
    }
  }

  /// - Note: Implicitly unwrapped optional so we can pass a reference of `self` to `MacroExpansionManager`.
  private(set) var generatedInterfaceManager: GeneratedInterfaceManager! {
    willSet {
      // Must only be set once.
      precondition(generatedInterfaceManager == nil)
      precondition(newValue != nil)
    }
  }

  var documentManager: DocumentManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentManager
    }
  }

  /// The build settings that were used to open the given files.
  ///
  ///  - Note: Not all documents open in `SwiftLanguageService` are necessarily in this dictionary because files where
  ///    `buildSettings(for:)` returns `nil` are not included.
  private var buildSettingsForOpenFiles: [DocumentURI: SwiftCompileCommand] = [:]

  /// Calling `scheduleCall` on `refreshDiagnosticsAndSemanticTokensDebouncer` schedules a `DiagnosticsRefreshRequest`
  /// and `WorkspaceSemanticTokensRefreshRequest` to be sent to to the client.
  ///
  /// We debounce these calls because the `DiagnosticsRefreshRequest` is a workspace-wide request. If we discover that
  /// the client should update diagnostics for file A and then discover that it should also update diagnostics for file
  /// B, we don't want to send two `DiagnosticsRefreshRequest`s. Instead, the two should be unified into a single
  /// request.
  private let refreshDiagnosticsAndSemanticTokensDebouncer: Debouncer<Void>

  /// Creates a language server for the given client using the sourcekitd dylib specified in `toolchain`.
  /// `reopenDocuments` is a closure that will be called if sourcekitd crashes and the `SwiftLanguageService` asks its
  /// parent server to reopen all of its documents.
  /// Returns `nil` if `sourcekitd` couldn't be found.
  package init?(
    sourceKitLSPServer: SourceKitLSPServer,
    toolchain: Toolchain,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    workspace: Workspace
  ) async throws {
    guard let sourcekitd = toolchain.sourcekitd else { return nil }
    self.sourcekitdPath = sourcekitd
    self.sourceKitLSPServer = sourceKitLSPServer
    self.swiftFormat = toolchain.swiftFormat
    let pluginPaths: PluginPaths?
    if let clientPlugin = options.sourcekitdOrDefault.clientPlugin,
      let servicePlugin = options.sourcekitdOrDefault.servicePlugin
    {
      pluginPaths = PluginPaths(
        clientPlugin: URL(fileURLWithPath: clientPlugin),
        servicePlugin: URL(fileURLWithPath: servicePlugin)
      )
    } else if let clientPlugin = toolchain.sourceKitClientPlugin, let servicePlugin = toolchain.sourceKitServicePlugin {
      pluginPaths = PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
    } else {
      logger.fault("Failed to find SourceKit plugin for toolchain at \(toolchain.path.path)")
      pluginPaths = nil
    }
    self.sourcekitd = try await SourceKitD.getOrCreate(dylibPath: sourcekitd, pluginPaths: pluginPaths)
    self.capabilityRegistry = workspace.capabilityRegistry
    self.semanticIndexManager = workspace.semanticIndexManager
    self.hooks = hooks
    self.state = .connected
    self.options = options

    // The debounce duration of 500ms was chosen arbitrarily without scientific research.
    self.refreshDiagnosticsAndSemanticTokensDebouncer = Debouncer(debounceDuration: .milliseconds(500)) {
      [weak sourceKitLSPServer] in
      guard let sourceKitLSPServer else {
        logger.fault(
          "Not sending diagnostic and semantic token refresh request to client because sourceKitLSPServer has been deallocated"
        )
        return
      }
      let clientCapabilities = await sourceKitLSPServer.capabilityRegistry?.clientCapabilities
      if clientCapabilities?.workspace?.diagnostics?.refreshSupport ?? false {
        _ = await orLog("Sending DiagnosticRefreshRequest to client after document dependencies updated") {
          try await sourceKitLSPServer.sendRequestToClient(DiagnosticsRefreshRequest())
        }
      } else {
        logger.debug("Not sending DiagnosticRefreshRequest because the client doesn't support it")
      }

      if clientCapabilities?.workspace?.semanticTokens?.refreshSupport ?? false {
        _ = await orLog("Sending WorkspaceSemanticTokensRefreshRequest to client after document dependencies updated") {
          try await sourceKitLSPServer.sendRequestToClient(WorkspaceSemanticTokensRefreshRequest())
        }
      } else {
        logger.debug("Not sending WorkspaceSemanticTokensRefreshRequest because the client doesn't support it")
      }
    }

    self.diagnosticReportManager = DiagnosticReportManager(
      sourcekitd: self.sourcekitd,
      options: options,
      syntaxTreeManager: syntaxTreeManager,
      documentManager: sourceKitLSPServer.documentManager,
      clientHasDiagnosticsCodeDescriptionSupport: await capabilityRegistry.clientHasDiagnosticsCodeDescriptionSupport
    )

    self.macroExpansionManager = MacroExpansionManager(swiftLanguageService: self)
    self.generatedInterfaceManager = GeneratedInterfaceManager(swiftLanguageService: self)

    // Create sub-directories for each type of generated file
    try FileManager.default.createDirectory(at: generatedInterfacesPath, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: generatedMacroExpansionsPath, withIntermediateDirectories: true)
  }

  /// - Important: For testing only
  package func setReusedNodeCallback(_ callback: (@Sendable (_ node: Syntax) -> ())?) async {
    await self.syntaxTreeManager.setReusedNodeCallback(callback)
  }

  /// Returns the latest snapshot of the given URI, generating the snapshot in case the URI is a reference document.
  func latestSnapshot(for uri: DocumentURI) async throws -> DocumentSnapshot {
    switch try? ReferenceDocumentURL(from: uri) {
    case .macroExpansion(let data):
      let content = try await self.macroExpansionManager.macroExpansion(for: data)
      return DocumentSnapshot(uri: uri, language: .swift, version: 0, lineTable: LineTable(content))
    case .generatedInterface(let data):
      return try await self.generatedInterfaceManager.snapshot(of: data)
    case nil:
      return try documentManager.latestSnapshot(uri)
    }
  }

  func buildSettings(for document: DocumentURI, fallbackAfterTimeout: Bool) async -> FileBuildSettings? {
    let buildSettingsFile = document.buildSettingsFile

    guard let sourceKitLSPServer else {
      logger.fault("Cannot retrieve build settings because SourceKitLSPServer is no longer alive")
      return nil
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: buildSettingsFile) else {
      return nil
    }
    return await workspace.buildSystemManager.buildSettingsInferredFromMainFile(
      for: buildSettingsFile,
      language: .swift,
      fallbackAfterTimeout: fallbackAfterTimeout
    )
  }

  func compileCommand(for document: DocumentURI, fallbackAfterTimeout: Bool) async -> SwiftCompileCommand? {
    if let settings = await self.buildSettings(for: document, fallbackAfterTimeout: fallbackAfterTimeout) {
      return SwiftCompileCommand(settings)
    } else {
      return nil
    }
  }

  func sendSourcekitdRequest(
    _ request: SKDRequestDictionary,
    fileContents: String?
  ) async throws -> SKDResponseDictionary {
    try await sourcekitd.send(
      request,
      timeout: options.sourcekitdRequestTimeoutOrDefault,
      restartTimeout: options.semanticServiceRestartTimeoutOrDefault,
      fileContents: fileContents
    )
  }

  package nonisolated func canHandle(workspace: Workspace, toolchain: Toolchain) -> Bool {
    return self.sourcekitdPath == toolchain.sourcekitd
  }

  private func setState(_ newState: LanguageServerState) async {
    let oldState = state
    state = newState
    for handler in stateChangeHandlers {
      handler(oldState, newState)
    }

    guard let sourceKitLSPServer else {
      return
    }
    switch (oldState, newState) {
    case (.connected, .connectionInterrupted), (.connected, .semanticFunctionalityDisabled):
      await sourceKitLSPServer.sourcekitdCrashedWorkDoneProgress.start()
    case (.connectionInterrupted, .connected), (.semanticFunctionalityDisabled, .connected):
      await sourceKitLSPServer.sourcekitdCrashedWorkDoneProgress.end()
      // We can provide diagnostics again now. Send a diagnostic refresh request to prompt the editor to reload
      // diagnostics.
      await refreshDiagnosticsAndSemanticTokensDebouncer.scheduleCall()
    case (.connected, .connected),
      (.connectionInterrupted, .connectionInterrupted),
      (.connectionInterrupted, .semanticFunctionalityDisabled),
      (.semanticFunctionalityDisabled, .connectionInterrupted),
      (.semanticFunctionalityDisabled, .semanticFunctionalityDisabled):
      break
    }
  }

  package func addStateChangeHandler(
    handler: @Sendable @escaping (_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void
  ) {
    self.stateChangeHandlers.append(handler)
  }
}

extension SwiftLanguageService {

  package func initialize(_ initialize: InitializeRequest) async throws -> InitializeResult {
    await sourcekitd.addNotificationHandler(self)

    return InitializeResult(
      capabilities: ServerCapabilities(
        textDocumentSync: .options(
          TextDocumentSyncOptions(
            openClose: true,
            change: .incremental
          )
        ),
        hoverProvider: .bool(true),
        completionProvider: CompletionOptions(
          resolveProvider: true,
          triggerCharacters: [".", "("]
        ),
        definitionProvider: nil,
        implementationProvider: .bool(true),
        referencesProvider: nil,
        documentHighlightProvider: .bool(true),
        documentSymbolProvider: .bool(true),
        codeActionProvider: .value(
          CodeActionServerCapabilities(
            clientCapabilities: initialize.capabilities.textDocument?.codeAction,
            codeActionOptions: CodeActionOptions(codeActionKinds: [.quickFix, .refactor]),
            supportsCodeActions: true
          )
        ),
        codeLensProvider: CodeLensOptions(),
        colorProvider: .bool(true),
        foldingRangeProvider: .bool(true),
        executeCommandProvider: ExecuteCommandOptions(
          commands: builtinSwiftCommands
        ),
        semanticTokensProvider: SemanticTokensOptions(
          legend: SemanticTokensLegend.sourceKitLSPLegend,
          range: .bool(true),
          full: .bool(true)
        ),
        inlayHintProvider: .value(InlayHintOptions(resolveProvider: false)),
        diagnosticProvider: DiagnosticOptions(
          interFileDependencies: true,
          workspaceDiagnostics: false
        )
      )
    )
  }

  package func clientInitialized(_: InitializedNotification) {
    // Nothing to do.
  }

  package func shutdown() async {
    await self.sourcekitd.removeNotificationHandler(self)
  }

  package func canonicalDeclarationPosition(of position: Position, in uri: DocumentURI) async -> Position? {
    guard let snapshot = try? documentManager.latestSnapshot(uri) else {
      return nil
    }
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let decl = syntaxTree.token(at: snapshot.absolutePosition(of: position))?.findParentOfSelf(
      ofType: DeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
    guard let decl else {
      return nil
    }
    return snapshot.position(of: decl.positionAfterSkippingLeadingTrivia)
  }

  /// Tell sourcekitd to crash itself. For testing purposes only.
  package func crash() async {
    let req = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.crashWithExit
    ])
    _ = try? await sendSourcekitdRequest(req, fileContents: nil)
  }

  // MARK: - Build System Integration

  package func reopenDocument(_ notification: ReopenTextDocumentNotification) async {
    switch try? ReferenceDocumentURL(from: notification.textDocument.uri) {
    case .macroExpansion, .generatedInterface:
      // Macro expansions and generated interfaces don't have document dependencies or build settings associated with
      // their URI. We should thus not not receive any `ReopenDocument` notifications for them.
      logger.fault("Unexpectedly received reopen document notification for reference document")
    case nil:
      let snapshot = orLog("Getting snapshot to re-open document") {
        try documentManager.latestSnapshot(notification.textDocument.uri)
      }
      guard let snapshot else {
        return
      }
      cancelInFlightPublishDiagnosticsTask(for: snapshot.uri)
      await diagnosticReportManager.removeItemsFromCache(with: snapshot.uri)

      let closeReq = closeDocumentSourcekitdRequest(uri: snapshot.uri)
      _ = await orLog("Closing document to re-open it") {
        try await self.sendSourcekitdRequest(closeReq, fileContents: nil)
      }

      let buildSettings = await compileCommand(for: snapshot.uri, fallbackAfterTimeout: true)
      let openReq = openDocumentSourcekitdRequest(
        snapshot: snapshot,
        compileCommand: buildSettings
      )
      self.buildSettingsForOpenFiles[snapshot.uri] = buildSettings
      _ = await orLog("Re-opening document") {
        try await self.sendSourcekitdRequest(openReq, fileContents: snapshot.text)
      }

      if await capabilityRegistry.clientSupportsPullDiagnostics(for: .swift) {
        await self.refreshDiagnosticsAndSemanticTokensDebouncer.scheduleCall()
      } else {
        await publishDiagnosticsIfNeeded(for: snapshot.uri)
      }
    }
  }

  package func documentUpdatedBuildSettings(_ uri: DocumentURI) async {
    guard (try? documentManager.openDocuments.contains(uri)) ?? false else {
      return
    }
    let newBuildSettings = await self.compileCommand(for: uri, fallbackAfterTimeout: false)
    if newBuildSettings != buildSettingsForOpenFiles[uri] {
      // Close and re-open the document internally to inform sourcekitd to update the compile command. At the moment
      // there's no better way to do this.
      // Schedule the document re-open in the SourceKit-LSP server. This ensures that the re-open happens exclusively with
      // no other request running at the same time.
      sourceKitLSPServer?.handle(ReopenTextDocumentNotification(textDocument: TextDocumentIdentifier(uri)))
    }
  }

  package func documentDependenciesUpdated(_ uris: Set<DocumentURI>) async {
    let uris = uris.filter { (try? documentManager.openDocuments.contains($0)) ?? false }
    guard !uris.isEmpty else {
      return
    }

    await orLog("Sending dependencyUpdated request to sourcekitd") {
      let req = sourcekitd.dictionary([
        keys.request: requests.dependencyUpdated
      ])
      _ = try await self.sendSourcekitdRequest(req, fileContents: nil)
    }
    // Even after sending the `dependencyUpdated` request to sourcekitd, the code completion session has state from
    // before the AST update. Close it and open a new code completion session on the next completion request.
    CodeCompletionSession.close(sourcekitd: sourcekitd, uris: uris)

    for uri in uris {
      await macroExpansionManager.purge(primaryFile: uri)
      sourceKitLSPServer?.handle(ReopenTextDocumentNotification(textDocument: TextDocumentIdentifier(uri)))
    }
  }

  // MARK: - Text synchronization

  func openDocumentSourcekitdRequest(
    snapshot: DocumentSnapshot,
    compileCommand: SwiftCompileCommand?
  ) -> SKDRequestDictionary {
    return sourcekitd.dictionary([
      keys.request: self.requests.editorOpen,
      keys.name: snapshot.uri.pseudoPath,
      keys.sourceText: snapshot.text,
      keys.enableSyntaxMap: 0,
      keys.enableStructure: 0,
      keys.enableDiagnostics: 0,
      keys.syntacticOnly: 1,
      keys.compilerArgs: compileCommand?.compilerArgs as [SKDRequestValue]?,
    ])
  }

  func closeDocumentSourcekitdRequest(uri: DocumentURI) -> SKDRequestDictionary {
    return sourcekitd.dictionary([
      keys.request: requests.editorClose,
      keys.name: uri.pseudoPath,
      keys.cancelBuilds: 0,
    ])
  }

  package func openDocument(_ notification: DidOpenTextDocumentNotification, snapshot: DocumentSnapshot) async {
    switch try? ReferenceDocumentURL(from: notification.textDocument.uri) {
    case .macroExpansion:
      break
    case .generatedInterface(let data):
      await orLog("Opening generated interface") {
        try await generatedInterfaceManager.open(document: data)
      }
    case nil:
      cancelInFlightPublishDiagnosticsTask(for: notification.textDocument.uri)
      await diagnosticReportManager.removeItemsFromCache(with: notification.textDocument.uri)

      let buildSettings = await self.compileCommand(for: snapshot.uri, fallbackAfterTimeout: true)
      buildSettingsForOpenFiles[snapshot.uri] = buildSettings

      let req = openDocumentSourcekitdRequest(snapshot: snapshot, compileCommand: buildSettings)
      await orLog("Opening sourcekitd document") {
        _ = try await self.sendSourcekitdRequest(req, fileContents: snapshot.text)
      }
      await publishDiagnosticsIfNeeded(for: notification.textDocument.uri)
    }
  }

  package func closeDocument(_ notification: DidCloseTextDocumentNotification) async {
    cancelInFlightPublishDiagnosticsTask(for: notification.textDocument.uri)
    inFlightPublishDiagnosticsTasks[notification.textDocument.uri] = nil
    await diagnosticReportManager.removeItemsFromCache(with: notification.textDocument.uri)
    buildSettingsForOpenFiles[notification.textDocument.uri] = nil
    switch try? ReferenceDocumentURL(from: notification.textDocument.uri) {
    case .macroExpansion:
      break
    case .generatedInterface(let data):
      await generatedInterfaceManager.close(document: data)
    case nil:
      let req = closeDocumentSourcekitdRequest(uri: notification.textDocument.uri)
      await orLog("Closing sourcekitd document") {
        _ = try await self.sendSourcekitdRequest(req, fileContents: nil)
      }
    }
  }

  /// Cancels any in-flight tasks to send a `PublishedDiagnosticsNotification` after edits.
  private func cancelInFlightPublishDiagnosticsTask(for document: DocumentURI) {
    if let inFlightTask = inFlightPublishDiagnosticsTasks[document] {
      inFlightTask.cancel()
    }
  }

  /// If the client doesn't support pull diagnostics, compute diagnostics for the latest version of the given document
  /// and send a `PublishDiagnosticsNotification` to the client for it.
  private func publishDiagnosticsIfNeeded(for document: DocumentURI) async {
    await withLoggingScope("publish-diagnostics") {
      await publishDiagnosticsIfNeededImpl(for: document)
    }
  }

  private func publishDiagnosticsIfNeededImpl(for document: DocumentURI) async {
    guard await !capabilityRegistry.clientSupportsPullDiagnostics(for: .swift) else {
      return
    }
    guard diagnosticsEnabled(for: document) else {
      return
    }
    cancelInFlightPublishDiagnosticsTask(for: document)
    inFlightPublishDiagnosticsTasks[document] = Task(priority: .medium) { [weak self] in
      guard let self, let sourceKitLSPServer = await self.sourceKitLSPServer else {
        logger.fault("Cannot produce PublishDiagnosticsNotification because sourceKitLSPServer was deallocated")
        return
      }
      do {
        // Sleep for a little bit until triggering the diagnostic generation. This effectively de-bounces diagnostic
        // generation since any later edit will cancel the previous in-flight task, which will thus never go on to send
        // the `DocumentDiagnosticsRequest`.
        try await Task.sleep(for: sourceKitLSPServer.options.swiftPublishDiagnosticsDebounceDurationOrDefault)
      } catch {
        return
      }
      do {
        let snapshot = try await self.latestSnapshot(for: document)
        let buildSettings = await self.compileCommand(for: document, fallbackAfterTimeout: false)
        let diagnosticReport = try await self.diagnosticReportManager.diagnosticReport(
          for: snapshot,
          buildSettings: buildSettings
        )
        let latestSnapshotID = try? await self.latestSnapshot(for: snapshot.uri).id
        if latestSnapshotID != snapshot.id {
          // Check that the document wasn't modified while we were getting diagnostics. This could happen because we are
          // calling `publishDiagnosticsIfNeeded` outside of `messageHandlingQueue` and thus a concurrent edit is
          // possible while we are waiting for the sourcekitd request to return a result.
          logger.log(
            """
            Document was modified while loading diagnostics. \
            Loaded diagnostics for \(snapshot.id.version, privacy: .public), \
            latest snapshot is \((latestSnapshotID?.version).map(String.init) ?? "<nil>", privacy: .public)
            """
          )
          throw CancellationError()
        }

        sourceKitLSPServer.sendNotificationToClient(
          PublishDiagnosticsNotification(
            uri: document,
            diagnostics: diagnosticReport.items
          )
        )
      } catch is CancellationError {
      } catch {
        logger.fault(
          """
          Failed to get diagnostics
          \(error.forLogging)
          """
        )
      }
    }
  }

  package func changeDocument(
    _ notification: DidChangeTextDocumentNotification,
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot,
    edits: [SourceEdit]
  ) async {
    cancelInFlightPublishDiagnosticsTask(for: notification.textDocument.uri)

    let keys = self.keys
    struct Edit {
      let offset: Int
      let length: Int
      let replacement: String
    }

    for edit in edits {
      let req = sourcekitd.dictionary([
        keys.request: self.requests.editorReplaceText,
        keys.name: notification.textDocument.uri.pseudoPath,
        keys.enableSyntaxMap: 0,
        keys.enableStructure: 0,
        keys.enableDiagnostics: 0,
        keys.syntacticOnly: 1,
        keys.offset: edit.range.lowerBound.utf8Offset,
        keys.length: edit.range.length.utf8Length,
        keys.sourceText: edit.replacement,
      ])
      do {
        _ = try await self.sendSourcekitdRequest(req, fileContents: nil)
      } catch {
        logger.fault(
          """
          Failed to replace \(edit.range.lowerBound.utf8Offset):\(edit.range.upperBound.utf8Offset) by \
          '\(edit.replacement)' in sourcekitd
          """
        )
      }
    }

    let concurrentEdits = ConcurrentEdits(
      fromSequential: edits
    )
    await syntaxTreeManager.registerEdit(
      preEditSnapshot: preEditSnapshot,
      postEditSnapshot: postEditSnapshot,
      edits: concurrentEdits
    )

    await publishDiagnosticsIfNeeded(for: notification.textDocument.uri)
  }

  package func willSaveDocument(_ notification: WillSaveTextDocumentNotification) {

  }

  package func didSaveDocument(_ notification: DidSaveTextDocumentNotification) {

  }

  // MARK: - Language features

  package func definition(_ request: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    throw ResponseError.unknown("unsupported method")
  }

  package func declaration(_ request: DeclarationRequest) async throws -> LocationsOrLocationLinksResponse? {
    throw ResponseError.unknown("unsupported method")
  }

  package func hover(_ req: HoverRequest) async throws -> HoverResponse? {
    let uri = req.textDocument.uri
    let position = req.position
    let cursorInfoResults = try await cursorInfo(uri, position..<position, fallbackSettingsAfterTimeout: false)
      .cursorInfo

    let symbolDocumentations = cursorInfoResults.compactMap { (cursorInfo) -> String? in
      if let documentation = cursorInfo.documentation {
        var result = ""
        if let annotatedDeclaration = cursorInfo.annotatedDeclaration {
          let markdownDecl =
            orLog("Convert XML declaration to Markdown") {
              try xmlDocumentationToMarkdown(annotatedDeclaration)
            } ?? annotatedDeclaration
          result += "\(markdownDecl)\n"
        }
        result += documentation
        return result
      } else if let annotated: String = cursorInfo.annotatedDeclaration {
        return """
          \(orLog("Convert XML to Markdown") { try xmlDocumentationToMarkdown(annotated) } ?? annotated)
          """
      } else {
        return nil
      }
    }

    if symbolDocumentations.isEmpty {
      return nil
    }

    let joinedDocumentation: String
    if let only = symbolDocumentations.only {
      joinedDocumentation = only
    } else {
      let documentationsWithSpacing = symbolDocumentations.enumerated().map { index, documentation in
        // Work around a bug in VS Code that displays a code block after a horizontal ruler without any spacing
        // (the pixels of the code block literally touch the ruler) by adding an empty line into the code block.
        // Only do this for subsequent results since only those are preceeded by a ruler.
        let prefix = "```swift\n"
        if index != 0 && documentation.starts(with: prefix) {
          return prefix + "\n" + documentation.dropFirst(prefix.count)
        } else {
          return documentation
        }
      }
      joinedDocumentation = """
        ## Multiple results

        \(documentationsWithSpacing.joined(separator: "\n\n---\n\n"))
        """
    }

    var tokenRange: Range<Position>?

    if let snapshot = try? await latestSnapshot(for: uri) {
      let tree = await syntaxTreeManager.syntaxTree(for: snapshot)
      if let token = tree.token(at: snapshot.absolutePosition(of: position)) {
        tokenRange = snapshot.absolutePositionRange(of: token.position..<token.endPosition)
      }
    }

    return HoverResponse(
      contents: .markupContent(MarkupContent(kind: .markdown, value: joinedDocumentation)),
      range: tokenRange
    )
  }

  package func documentColor(_ req: DocumentColorRequest) async throws -> [ColorInformation] {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    class ColorLiteralFinder: SyntaxVisitor {
      let snapshot: DocumentSnapshot
      var result: [ColorInformation] = []

      init(snapshot: DocumentSnapshot) {
        self.snapshot = snapshot
        super.init(viewMode: .sourceAccurate)
      }

      override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.macroName.text == "colorLiteral" else {
          return .visitChildren
        }
        func extractArgument(_ argumentName: String, from arguments: LabeledExprListSyntax) -> Double? {
          for argument in arguments {
            if argument.label?.text == argumentName {
              if let integer = argument.expression.as(IntegerLiteralExprSyntax.self) {
                return Double(integer.literal.text)
              } else if let integer = argument.expression.as(FloatLiteralExprSyntax.self) {
                return Double(integer.literal.text)
              }
            }
          }
          return nil
        }
        guard let red = extractArgument("red", from: node.arguments),
          let green = extractArgument("green", from: node.arguments),
          let blue = extractArgument("blue", from: node.arguments),
          let alpha = extractArgument("alpha", from: node.arguments)
        else {
          return .skipChildren
        }

        result.append(
          ColorInformation(
            range: snapshot.absolutePositionRange(of: node.position..<node.endPosition),
            color: Color(red: red, green: green, blue: blue, alpha: alpha)
          )
        )

        return .skipChildren
      }
    }

    try Task.checkCancellation()

    let colorLiteralFinder = ColorLiteralFinder(snapshot: snapshot)
    colorLiteralFinder.walk(syntaxTree)
    return colorLiteralFinder.result
  }

  package func colorPresentation(_ req: ColorPresentationRequest) async throws -> [ColorPresentation] {
    let color = req.color
    // Empty string as a label breaks VSCode color picker
    let label = "Color Literal"
    let newText = "#colorLiteral(red: \(color.red), green: \(color.green), blue: \(color.blue), alpha: \(color.alpha))"
    let textEdit = TextEdit(range: req.range, newText: newText)
    let presentation = ColorPresentation(label: label, textEdit: textEdit, additionalTextEdits: nil)
    return [presentation]
  }

  package func documentSymbolHighlight(_ req: DocumentHighlightRequest) async throws -> [DocumentHighlight]? {
    let snapshot = try await self.latestSnapshot(for: req.textDocument.uri)

    let relatedIdentifiers = try await self.relatedIdentifiers(
      at: req.position,
      in: snapshot,
      includeNonEditableBaseNames: false
    )
    return relatedIdentifiers.relatedIdentifiers.map {
      DocumentHighlight(
        range: $0.range,
        kind: .read  // unknown
      )
    }
  }

  package func codeAction(_ req: CodeActionRequest) async throws -> CodeActionRequestResponse? {
    if (try? ReferenceDocumentURL(from: req.textDocument.uri)) != nil {
      // Do not show code actions in reference documents
      return nil
    }
    let providersAndKinds: [(provider: CodeActionProvider, kind: CodeActionKind?)] = [
      (retrieveSyntaxCodeActions, nil),
      (retrieveRefactorCodeActions, .refactor),
      (retrieveQuickFixCodeActions, .quickFix),
    ]
    let wantedActionKinds = req.context.only
    let providers: [CodeActionProvider] = providersAndKinds.compactMap {
      if let wantedActionKinds, let kind = $0.1, !wantedActionKinds.contains(kind) {
        return nil
      }

      return $0.provider
    }
    let codeActionCapabilities = capabilityRegistry.clientCapabilities.textDocument?.codeAction
    let codeActions = try await retrieveCodeActions(req, providers: providers)
    let response = CodeActionRequestResponse(
      codeActions: codeActions,
      clientCapabilities: codeActionCapabilities
    )
    return response
  }

  func retrieveCodeActions(
    _ req: CodeActionRequest,
    providers: [CodeActionProvider]
  ) async throws -> [CodeAction] {
    guard providers.isEmpty == false else {
      return []
    }
    return await providers.concurrentMap { provider in
      do {
        return try await provider(req)
      } catch {
        // Ignore any providers that failed to provide refactoring actions.
        return []
      }
    }
    .flatMap { $0 }
  }

  func retrieveSyntaxCodeActions(_ request: CodeActionRequest) async throws -> [CodeAction] {
    let uri = request.textDocument.uri
    let snapshot = try documentManager.latestSnapshot(uri)

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    guard let scope = SyntaxCodeActionScope(snapshot: snapshot, syntaxTree: syntaxTree, request: request) else {
      return []
    }
    return await allSyntaxCodeActions.concurrentMap { provider in
      return provider.codeActions(in: scope)
    }.flatMap { $0 }
  }

  func retrieveRefactorCodeActions(_ params: CodeActionRequest) async throws -> [CodeAction] {
    let additionalCursorInfoParameters: ((SKDRequestDictionary) -> Void) = { skreq in
      skreq.set(self.keys.retrieveRefactorActions, to: 1)
    }

    let cursorInfoResponse = try await cursorInfo(
      params.textDocument.uri,
      params.range,
      fallbackSettingsAfterTimeout: true,
      additionalParameters: additionalCursorInfoParameters
    )

    var canInlineMacro = false

    var refactorActions = cursorInfoResponse.refactorActions.compactMap {
      let lspCommand = $0.asCommand()
      if !canInlineMacro {
        canInlineMacro = $0.actionString == "source.refactoring.kind.inline.macro"
      }

      return CodeAction(title: $0.title, kind: .refactor, command: lspCommand)
    }

    if canInlineMacro {
      let expandMacroCommand = ExpandMacroCommand(positionRange: params.range, textDocument: params.textDocument)
        .asCommand()

      refactorActions.append(CodeAction(title: expandMacroCommand.title, kind: .refactor, command: expandMacroCommand))
    }

    return refactorActions
  }

  func retrieveQuickFixCodeActions(_ params: CodeActionRequest) async throws -> [CodeAction] {
    let snapshot = try await self.latestSnapshot(for: params.textDocument.uri)
    let buildSettings = await self.compileCommand(for: params.textDocument.uri, fallbackAfterTimeout: true)
    let diagnosticReport = try await self.diagnosticReportManager.diagnosticReport(
      for: snapshot,
      buildSettings: buildSettings
    )

    let codeActions = diagnosticReport.items.flatMap { (diag) -> [CodeAction] in
      let codeActions: [CodeAction] =
        (diag.codeActions ?? []) + (diag.relatedInformation?.flatMap { $0.codeActions ?? [] } ?? [])

      if codeActions.isEmpty {
        // The diagnostic doesn't have fix-its. Don't return anything.
        return []
      }

      // Check if the diagnostic overlaps with the selected range.
      guard params.range.overlapsIncludingEmptyRanges(other: diag.range) else {
        return []
      }

      // Check if the set of diagnostics provided by the request contains this diagnostic.
      // For this, only compare the 'basic' properties of the diagnostics, excluding related information and code actions since
      // code actions are only defined in an LSP extension and might not be sent back to us.
      guard
        params.context.diagnostics.contains(where: { (contextDiag) -> Bool in
          return contextDiag.range == diag.range && contextDiag.severity == diag.severity
            && contextDiag.code == diag.code && contextDiag.source == diag.source && contextDiag.message == diag.message
        })
      else {
        return []
      }

      // Flip the attachment of diagnostic to code action instead of the code action being attached to the diagnostic
      return codeActions.map({
        var codeAction = $0
        var diagnosticWithoutCodeActions = diag
        diagnosticWithoutCodeActions.codeActions = nil
        if let related = diagnosticWithoutCodeActions.relatedInformation {
          diagnosticWithoutCodeActions.relatedInformation = related.map {
            var withoutCodeActions = $0
            withoutCodeActions.codeActions = nil
            return withoutCodeActions
          }
        }
        codeAction.diagnostics = [diagnosticWithoutCodeActions]
        return codeAction
      })
    }

    return codeActions
  }

  package func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
    let uri = req.textDocument.uri
    let infos = try await variableTypeInfos(uri, req.range)
    let hints = infos
      .lazy
      .filter { !$0.hasExplicitType }
      .map { info -> InlayHint in
        let position = info.range.upperBound
        let label = ": \(info.printedType)"
        let textEdits: [TextEdit]?
        if info.canBeFollowedByTypeAnnotation {
          textEdits = [TextEdit(range: position..<position, newText: label)]
        } else {
          textEdits = nil
        }
        return InlayHint(
          position: position,
          label: .string(label),
          kind: .type,
          textEdits: textEdits
        )
      }

    return Array(hints)
  }

  package func codeLens(_ req: CodeLensRequest) async throws -> [CodeLens] {
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    var targetDisplayName: String? = nil
    if let workspace = await sourceKitLSPServer?.workspaceForDocument(uri: req.textDocument.uri),
      let target = await workspace.buildSystemManager.canonicalTarget(for: req.textDocument.uri),
      let buildTarget = await workspace.buildSystemManager.buildTarget(named: target)
    {
      targetDisplayName = buildTarget.displayName
    }
    return await SwiftCodeLensScanner.findCodeLenses(
      in: snapshot,
      syntaxTreeManager: self.syntaxTreeManager,
      targetName: targetDisplayName,
      supportedCommands: self.capabilityRegistry.supportedCodeLensCommands
    )
  }

  package func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport {
    do {
      switch try? ReferenceDocumentURL(from: req.textDocument.uri) {
      case .generatedInterface:
        // Generated interfaces don't have diagnostics associated with them.
        return .full(RelatedFullDocumentDiagnosticReport(items: []))
      case .macroExpansion, nil: break
      }

      await semanticIndexManager?.prepareFileForEditorFunctionality(
        req.textDocument.uri.buildSettingsFile
      )
      let snapshot = try await self.latestSnapshot(for: req.textDocument.uri)
      let buildSettings = await self.compileCommand(for: req.textDocument.uri, fallbackAfterTimeout: false)
      try Task.checkCancellation()
      let diagnosticReport = try await self.diagnosticReportManager.diagnosticReport(
        for: snapshot,
        buildSettings: buildSettings
      )
      return .full(diagnosticReport)
    } catch {
      // VS Code does not request diagnostics again for a document if the diagnostics request failed.
      // Since sourcekit-lsp usually recovers from failures (e.g. after sourcekitd crashes), this is undesirable.
      // Instead of returning an error, return empty results.
      // Do forward cancellation because we don't want to clear diagnostics in the client if they cancel the diagnostic
      // request.
      if ResponseError(error) == .cancelled {
        throw error
      }
      logger.error(
        """
        Loading diagnostic failed with the following error. Returning empty diagnostics.
        \(error.forLogging)
        """
      )
      return .full(RelatedFullDocumentDiagnosticReport(items: []))
    }
  }

  package func indexedRename(_ request: IndexedRenameRequest) async throws -> WorkspaceEdit? {
    throw ResponseError.unknown("unsupported method")
  }

  package func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny? {
    if let command = req.swiftCommand(ofType: SemanticRefactorCommand.self) {
      try await semanticRefactoring(command)
    } else if let command = req.swiftCommand(ofType: ExpandMacroCommand.self) {
      try await expandMacro(command)
    } else {
      throw ResponseError.unknown("unknown command \(req.command)")
    }

    return nil
  }

  package func getReferenceDocument(_ req: GetReferenceDocumentRequest) async throws -> GetReferenceDocumentResponse {
    let referenceDocumentURL = try ReferenceDocumentURL(from: req.uri)

    switch referenceDocumentURL {
    case let .macroExpansion(data):
      return GetReferenceDocumentResponse(
        content: try await macroExpansionManager.macroExpansion(for: data)
      )
    case .generatedInterface(let data):
      return GetReferenceDocumentResponse(
        content: try await generatedInterfaceManager.snapshot(of: data).text
      )
    }
  }
}

extension SwiftLanguageService: SKDNotificationHandler {
  package nonisolated func notification(_ notification: SKDResponse) {
    sourcekitdNotificationHandlingQueue.async {
      await self.notificationImpl(notification)
    }
  }

  private func notificationImpl(_ notification: SKDResponse) async {
    logger.debug(
      """
      Received notification from sourcekitd
      \(notification.forLogging)
      """
    )
    // Check if we need to update our `state` based on the contents of the notification.
    if notification.value?[self.keys.notification] == self.values.semaEnabledNotification {
      await self.setState(.connected)
      return
    }

    if self.state == .connectionInterrupted {
      // If we get a notification while we are restoring the connection, it means that the server has restarted.
      // We still need to wait for semantic functionality to come back up.
      await self.setState(.semanticFunctionalityDisabled)

      // Ask our parent to re-open all of our documents.
      if let sourceKitLSPServer {
        await sourceKitLSPServer.reopenDocuments(for: self)
      } else {
        logger.fault("Cannot reopen documents because SourceKitLSPServer is no longer alive")
      }
    }

    if notification.error == .connectionInterrupted {
      await self.setState(.connectionInterrupted)
    }
  }
}

// MARK: - Position conversion

/// A line:column position as it is used in sourcekitd, using UTF-8 for the column index and using a one-based line and
/// column number.
struct SourceKitDPosition {
  /// Line number within a document (one-based).
  public var line: Int

  /// UTF-8 code-unit offset from the start of a line (1-based).
  public var utf8Column: Int
}

extension DocumentSnapshot {

  // MARK: String.Index <-> Raw UTF-8

  /// Converts the given UTF-8 offset to `String.Index`.
  ///
  /// If the offset is out-of-bounds of the snapshot, returns the closest valid index and logs a fault containing the
  /// file and line of the caller (from `callerFile` and `callerLine`).
  func indexOf(utf8Offset: Int, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> String.Index {
    guard utf8Offset >= 0 else {
      logger.fault(
        """
        UTF-8 offset \(utf8Offset) is negative while converting it to String.Index \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return text.startIndex
    }
    guard let index = text.utf8.index(text.startIndex, offsetBy: utf8Offset, limitedBy: text.endIndex) else {
      logger.fault(
        """
        UTF-8 offset \(utf8Offset) is past end of file while converting it to String.Index \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return text.endIndex
    }
    return index
  }

  // MARK: Position <-> Raw UTF-8 offset

  /// Converts the given UTF-16-based line:column position to the UTF-8 offset of that position within the source file.
  ///
  /// If `position` does not refer to a valid position with in the snapshot, returns the offset of the closest valid
  /// position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  func utf8Offset(of position: Position, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> Int {
    return lineTable.utf8OffsetOf(
      line: position.line,
      utf16Column: position.utf16index,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  /// Converts the given UTF-8 offset to a UTF-16-based line:column position.
  ///
  /// If the offset is after the end of the snapshot, returns `nil` and logs a fault containing the file and line of
  /// the caller (from `callerFile` and `callerLine`).
  func positionOf(utf8Offset: Int, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> Position {
    let (line, utf16Column) = lineTable.lineAndUTF16ColumnOf(
      utf8Offset: utf8Offset,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return Position(line: line, utf16index: utf16Column)
  }

  /// Converts the given UTF-16 based line:column range to a UTF-8 based offset range.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  func utf8OffsetRange(
    of range: Range<Position>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<Int> {
    let startOffset = utf8Offset(of: range.lowerBound, callerFile: callerFile, callerLine: callerLine)
    let endOffset = utf8Offset(of: range.upperBound, callerFile: callerFile, callerLine: callerLine)
    return startOffset..<endOffset
  }

  // MARK: Position <-> String.Index

  /// Converts the given UTF-16-based `line:column` position to a `String.Index`.
  ///
  /// If `position` does not refer to a valid position with in the snapshot, returns the index of the closest valid
  /// position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  func index(of position: Position, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> String.Index {
    return lineTable.stringIndexOf(
      line: position.line,
      utf16Column: position.utf16index,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  /// Converts the given UTF-16-based `line:column` range to a `String.Index` range.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  func indexRange(
    of range: Range<Position>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<String.Index> {
    return self.index(of: range.lowerBound)..<self.index(of: range.upperBound)
  }

  /// Converts the given UTF-8 based line:column position to a UTF-16 based line-column position.
  ///
  /// If the UTF-8 based line:column pair does not refer to a valid position within the snapshot, returns the closest
  /// valid position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  func positionOf(
    zeroBasedLine: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    let utf16Column = lineTable.utf16ColumnAt(
      line: zeroBasedLine,
      utf8Column: utf8Column,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return Position(line: zeroBasedLine, utf16index: utf16Column)
  }

  /// Converts the given `String.Index` to a UTF-16-based line:column position.
  func position(of index: String.Index, fromLine: Int = 0) -> Position {
    let (line, utf16Column) = lineTable.lineAndUTF16ColumnOf(index, fromLine: fromLine)
    return Position(line: line, utf16index: utf16Column)
  }

  // MARK: Position <-> AbsolutePosition

  /// Converts the given UTF-8-offset-based `AbsolutePosition` to a UTF-16-based line:column.
  ///
  /// If the `AbsolutePosition` out of bounds of the source file, returns the closest valid position and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  func position(
    of position: AbsolutePosition,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    return positionOf(utf8Offset: position.utf8Offset, callerFile: callerFile, callerLine: callerLine)
  }

  /// Converts the given UTF-16-based line:column `Position` to a UTF-8-offset-based `AbsolutePosition`.
  ///
  /// If the UTF-16 based line:column pair does not refer to a valid position within the snapshot, returns the closest
  /// valid position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  func absolutePosition(
    of position: Position,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> AbsolutePosition {
    let offset = utf8Offset(of: position, callerFile: callerFile, callerLine: callerLine)
    return AbsolutePosition(utf8Offset: offset)
  }

  /// Converts the lower and upper bound of the given UTF-8-offset-based `AbsolutePosition` range to a UTF-16-based
  /// line:column range for use in LSP.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  func absolutePositionRange(
    of range: Range<AbsolutePosition>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<Position> {
    let lowerBound = self.position(of: range.lowerBound, callerFile: callerFile, callerLine: callerLine)
    let upperBound = self.position(of: range.upperBound, callerFile: callerFile, callerLine: callerLine)
    return lowerBound..<upperBound
  }

  /// Extracts the range of the given syntax node in terms of positions within
  /// this source file.
  func range(
    of node: some SyntaxProtocol,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<Position> {
    let lowerBound = self.position(of: node.position, callerFile: callerFile, callerLine: callerLine)
    let upperBound = self.position(of: node.endPosition, callerFile: callerFile, callerLine: callerLine)
    return lowerBound..<upperBound
  }

  /// Converts the given UTF-16-based line:column range to a UTF-8-offset-based `ByteSourceRange`.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  func byteSourceRange(
    of range: Range<Position>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<AbsolutePosition> {
    let utf8OffsetRange = utf8OffsetRange(of: range, callerFile: callerFile, callerLine: callerLine)
    return Range<AbsolutePosition>(
      position: AbsolutePosition(utf8Offset: utf8OffsetRange.startIndex),
      length: SourceLength(utf8Length: utf8OffsetRange.count)
    )
  }

  // MARK: Position <-> RenameLocation

  /// Converts the given UTF-8-based line:column `RenamedLocation` to a UTF-16-based line:column `Position`.
  ///
  /// If the UTF-8 based line:column pair does not refer to a valid position within the snapshot, returns the closest
  /// valid position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  func position(
    of renameLocation: RenameLocation,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    return positionOf(
      zeroBasedLine: renameLocation.line - 1,
      utf8Column: renameLocation.utf8Column - 1,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  // MARK: Position <-> SourceKitDPosition

  func sourcekitdPosition(
    of position: Position,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> SourceKitDPosition {
    let utf8Column = lineTable.utf8ColumnAt(
      line: position.line,
      utf16Column: position.utf16index,
      callerFile: callerFile,
      callerLine: callerLine
    )
    // FIXME: Introduce new type for UTF-8 based positions
    return SourceKitDPosition(line: position.line + 1, utf8Column: utf8Column + 1)
  }

  // MAR: Position <-> SymbolLocation

  /// Converts the given UTF-8-offset-based `SymbolLocation` to a UTF-16-based line:column `Position`.
  ///
  /// If the UTF-8 offset is out-of-bounds of the snapshot, returns the closest valid position and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  func position(
    of symbolLocation: SymbolLocation,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    return positionOf(
      zeroBasedLine: symbolLocation.line - 1,
      utf8Column: symbolLocation.utf8Column - 1,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  // MARK: AbsolutePosition <-> RenameLocation

  /// Converts the given UTF-8-based line:column `RenamedLocation` to a UTF-8-offset-based `AbsolutePosition`.
  ///
  /// If the UTF-8 based line:column pair does not refer to a valid position within the snapshot, returns the offset of
  /// the closest valid position and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  func absolutePosition(
    of renameLocation: RenameLocation,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> AbsolutePosition {
    let utf8Offset = lineTable.utf8OffsetOf(
      line: renameLocation.line - 1,
      utf8Column: renameLocation.utf8Column - 1,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return AbsolutePosition(utf8Offset: utf8Offset)
  }
}

extension sourcekitd_api_uid_t {
  func isCommentKind(_ vals: sourcekitd_api_values) -> Bool {
    switch self {
    case vals.comment, vals.commentMarker, vals.commentURL:
      return true
    default:
      return isDocCommentKind(vals)
    }
  }

  func isDocCommentKind(_ vals: sourcekitd_api_values) -> Bool {
    return self == vals.docComment || self == vals.docCommentField
  }

  func asCompletionItemKind(_ vals: sourcekitd_api_values) -> CompletionItemKind? {
    switch self {
    case vals.completionKindKeyword:
      return .keyword
    case vals.declModule:
      return .module
    case vals.declClass:
      return .class
    case vals.declStruct:
      return .struct
    case vals.declEnum:
      return .enum
    case vals.declEnumElement:
      return .enumMember
    case vals.declProtocol:
      return .interface
    case vals.declAssociatedType:
      return .typeParameter
    case vals.declTypeAlias:
      return .typeParameter
    case vals.declGenericTypeParam:
      return .typeParameter
    case vals.declConstructor:
      return .constructor
    case vals.declDestructor:
      return .value
    case vals.declSubscript:
      return .method
    case vals.declMethodStatic:
      return .method
    case vals.declMethodInstance:
      return .method
    case vals.declFunctionPrefixOperator,
      vals.declFunctionPostfixOperator,
      vals.declFunctionInfixOperator:
      return .operator
    case vals.declPrecedenceGroup:
      return .value
    case vals.declFunctionFree:
      return .function
    case vals.declVarStatic, vals.declVarClass:
      return .property
    case vals.declVarInstance:
      return .property
    case vals.declVarLocal,
      vals.declVarGlobal,
      vals.declVarParam:
      return .variable
    default:
      return nil
    }
  }

  func asSymbolKind(_ vals: sourcekitd_api_values) -> SymbolKind? {
    switch self {
    case vals.declClass, vals.refClass, vals.declActor, vals.refActor:
      return .class
    case vals.declMethodInstance, vals.refMethodInstance,
      vals.declMethodStatic, vals.refMethodStatic,
      vals.declMethodClass, vals.refMethodClass:
      return .method
    case vals.declVarInstance, vals.refVarInstance,
      vals.declVarStatic, vals.refVarStatic,
      vals.declVarClass, vals.refVarClass:
      return .property
    case vals.declEnum, vals.refEnum:
      return .enum
    case vals.declEnumElement, vals.refEnumElement:
      return .enumMember
    case vals.declProtocol, vals.refProtocol:
      return .interface
    case vals.declFunctionFree, vals.refFunctionFree:
      return .function
    case vals.declVarGlobal, vals.refVarGlobal,
      vals.declVarLocal, vals.refVarLocal:
      return .variable
    case vals.declStruct, vals.refStruct:
      return .struct
    case vals.declGenericTypeParam, vals.refGenericTypeParam:
      return .typeParameter
    case vals.declExtension:
      // There are no extensions in LSP, so we return something vaguely similar
      return .namespace
    case vals.refModule:
      return .module
    case vals.declConstructor, vals.refConstructor:
      return .constructor
    default:
      return nil
    }
  }
}
