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

import Dispatch
import Foundation
import LSPLogging
import LanguageServerProtocol
import SKCore
import SKSupport
import SourceKitD
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

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

/// Explicitly blacklisted `DocumentURI` schemes.
fileprivate let excludedDocumentURISchemes: [String] = [
  "git",
  "hg",
]

/// Returns true if diagnostics should be emitted for the given document.
///
/// Some editors  (like Visual Studio Code) use non-file URLs to manage source control diff bases
/// for the active document, which can lead to duplicate diagnostics in the Problems view.
/// As a workaround we explicitly blacklist those URIs and don't emit diagnostics for them.
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
public struct SwiftCompileCommand: Equatable {

  /// The compiler arguments, including working directory. This is required since sourcekitd only
  /// accepts the working directory via the compiler arguments.
  public let compilerArgs: [String]

  /// Whether the compiler arguments are considered fallback - we withhold diagnostics for
  /// fallback arguments and represent the file state differently.
  public let isFallback: Bool

  public init(_ settings: FileBuildSettings) {
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

public actor SwiftLanguageServer: ToolchainLanguageServer {
  /// The ``SourceKitServer`` instance that created this `ClangLanguageServerShim`.
  weak var sourceKitServer: SourceKitServer?

  let sourcekitd: SourceKitD

  /// Queue on which notifications from sourcekitd are handled to ensure we are
  /// handling them in-order.
  let sourcekitdNotificationHandlingQueue = AsyncQueue<Serial>()

  let capabilityRegistry: CapabilityRegistry

  let serverOptions: SourceKitServer.Options

  /// Directory where generated Swift interfaces will be stored.
  let generatedInterfacesPath: URL

  // FIXME: ideally we wouldn't need separate management from a parent server in the same process.
  var documentManager: DocumentManager

  /// For each edited document, the last task that was triggered to send a `PublishDiagnosticsNotification`.
  ///
  /// This is used to cancel previous publish diagnostics tasks if an edit is made to a document.
  ///
  /// - Note: We only clear entries from the dictionary when a document is closed. The task that the document maps to
  ///   might have finished. This isn't an issue since the tasks do not retain `self`.
  private var inFlightPublishDiagnosticsTasks: [DocumentURI: Task<Void, Never>] = [:]

  let syntaxTreeManager = SyntaxTreeManager()

  nonisolated var keys: sourcekitd_keys { return sourcekitd.keys }
  nonisolated var requests: sourcekitd_requests { return sourcekitd.requests }
  nonisolated var values: sourcekitd_values { return sourcekitd.values }

  var enablePublishDiagnostics: Bool {
    // Since LSP 3.17.0, diagnostics can be reported through pull-based requests,
    // in addition to the existing push-based publish notifications.
    // If the client supports pull diagnostics, we report the capability
    // and we should disable the publish notifications to avoid double-reporting.
    return capabilityRegistry.pullDiagnosticsRegistration(for: .swift) == nil
  }

  private var state: LanguageServerState {
    didSet {
      for handler in stateChangeHandlers {
        handler(oldValue, state)
      }
    }
  }

  private var stateChangeHandlers: [(_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void] = []

  private let diagnosticReportManager: DiagnosticReportManager

  /// Creates a language server for the given client using the sourcekitd dylib specified in `toolchain`.
  /// `reopenDocuments` is a closure that will be called if sourcekitd crashes and the `SwiftLanguageServer` asks its parent server to reopen all of its documents.
  /// Returns `nil` if `sourcektid` couldn't be found.
  public init?(
    sourceKitServer: SourceKitServer,
    toolchain: Toolchain,
    options: SourceKitServer.Options,
    workspace: Workspace
  ) throws {
    guard let sourcekitd = toolchain.sourcekitd else { return nil }
    self.sourceKitServer = sourceKitServer
    self.sourcekitd = try SourceKitDImpl.getOrCreate(dylibPath: sourcekitd)
    self.capabilityRegistry = workspace.capabilityRegistry
    self.serverOptions = options
    self.documentManager = DocumentManager()
    self.state = .connected
    self.generatedInterfacesPath = options.generatedInterfacesPath.asURL
    try FileManager.default.createDirectory(at: generatedInterfacesPath, withIntermediateDirectories: true)
    self.diagnosticReportManager = DiagnosticReportManager(
      sourcekitd: self.sourcekitd,
      syntaxTreeManager: syntaxTreeManager,
      documentManager: documentManager,
      clientHasDiagnosticsCodeDescriptionSupport: capabilityRegistry.clientHasDiagnosticsCodeDescriptionSupport
    )
  }

  /// - Important: For testing only
  public func setReusedNodeCallback(_ callback: ReusedNodeCallback?) async {
    await self.syntaxTreeManager.setReusedNodeCallback(callback)
  }

  func buildSettings(for document: DocumentURI) async -> SwiftCompileCommand? {
    guard let sourceKitServer else {
      logger.fault("Cannot retrieve build settings because SourceKitServer is no longer alive")
      return nil
    }
    guard let workspace = await sourceKitServer.workspaceForDocument(uri: document) else {
      return nil
    }
    if let settings = await workspace.buildSystemManager.buildSettingsInferredFromMainFile(
      for: document,
      language: .swift
    ) {
      return SwiftCompileCommand(settings)
    } else {
      return nil
    }
  }

  public nonisolated func canHandle(workspace: Workspace) -> Bool {
    // We have a single sourcekitd instance for all workspaces.
    return true
  }

  public func addStateChangeHandler(
    handler: @escaping (_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void
  ) {
    self.stateChangeHandlers.append(handler)
  }
}

extension SwiftLanguageServer {

  public func initialize(_ initialize: InitializeRequest) throws -> InitializeResult {
    sourcekitd.addNotificationHandler(self)

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
          resolveProvider: false,
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
        colorProvider: .bool(true),
        foldingRangeProvider: .bool(true),
        executeCommandProvider: ExecuteCommandOptions(
          commands: builtinSwiftCommands
        ),
        semanticTokensProvider: SemanticTokensOptions(
          legend: SemanticTokensLegend(
            tokenTypes: SemanticTokenTypes.all.map(\.name),
            tokenModifiers: SemanticTokenModifiers.all.compactMap(\.name)
          ),
          range: .bool(true),
          full: .bool(true)
        ),
        inlayHintProvider: .value(
          InlayHintOptions(
            resolveProvider: false
          )
        ),
        diagnosticProvider: DiagnosticOptions(
          interFileDependencies: true,
          workspaceDiagnostics: false
        )
      )
    )
  }

  public func clientInitialized(_: InitializedNotification) {
    // Nothing to do.
  }

  public func shutdown() async {
    self.sourcekitd.removeNotificationHandler(self)
  }

  /// Tell sourcekitd to crash itself. For testing purposes only.
  public func _crash() async {
    let req = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.crash_exit
    ])
    _ = try? await sourcekitd.send(req, fileContents: nil)
  }

  // MARK: - Build System Integration

  private func reopenDocument(_ snapshot: DocumentSnapshot, _ compileCmd: SwiftCompileCommand?) async {
    cancelInFlightPublishDiagnosticsTask(for: snapshot.uri)
    await diagnosticReportManager.removeItemsFromCache(with: snapshot.id.uri)

    let keys = self.keys
    let path = snapshot.uri.pseudoPath

    let closeReq = sourcekitd.dictionary([
      keys.request: requests.editor_close,
      keys.name: path,
    ])
    _ = try? await self.sourcekitd.send(closeReq, fileContents: nil)

    let openReq = sourcekitd.dictionary([
      keys.request: self.requests.editor_open,
      keys.name: path,
      keys.sourcetext: snapshot.text,
      keys.compilerargs: compileCmd?.compilerArgs as [SKDValue]?,
    ])

    _ = try? await self.sourcekitd.send(openReq, fileContents: snapshot.text)

    publishDiagnosticsIfNeeded(for: snapshot.uri)
  }

  public func documentUpdatedBuildSettings(_ uri: DocumentURI) async {
    // We may not have a snapshot if this is called just before `openDocument`.
    guard let snapshot = try? self.documentManager.latestSnapshot(uri) else {
      return
    }

    // Close and re-open the document internally to inform sourcekitd to update the compile
    // command. At the moment there's no better way to do this.
    await self.reopenDocument(snapshot, await self.buildSettings(for: uri))
  }

  public func documentDependenciesUpdated(_ uri: DocumentURI) async {
    guard let snapshot = try? self.documentManager.latestSnapshot(uri) else {
      return
    }

    // Forcefully reopen the document since the `BuildSystem` has informed us
    // that the dependencies have changed and the AST needs to be reloaded.
    await self.reopenDocument(snapshot, self.buildSettings(for: uri))
  }

  // MARK: - Text synchronization

  public func openDocument(_ note: DidOpenTextDocumentNotification) async {
    cancelInFlightPublishDiagnosticsTask(for: note.textDocument.uri)
    await diagnosticReportManager.removeItemsFromCache(with: note.textDocument.uri)

    let keys = self.keys

    guard let snapshot = self.documentManager.open(note) else {
      // Already logged failure.
      return
    }

    let req = sourcekitd.dictionary([
      keys.request: self.requests.editor_open,
      keys.name: note.textDocument.uri.pseudoPath,
      keys.sourcetext: snapshot.text,
      keys.syntactic_only: 1,
      keys.compilerargs: await self.buildSettings(for: snapshot.uri)?.compilerArgs as [SKDValue]?,
    ])

    _ = try? await self.sourcekitd.send(req, fileContents: snapshot.text)
    publishDiagnosticsIfNeeded(for: note.textDocument.uri)
  }

  public func closeDocument(_ note: DidCloseTextDocumentNotification) async {
    cancelInFlightPublishDiagnosticsTask(for: note.textDocument.uri)
    inFlightPublishDiagnosticsTasks[note.textDocument.uri] = nil
    await diagnosticReportManager.removeItemsFromCache(with: note.textDocument.uri)

    let keys = self.keys

    self.documentManager.close(note)

    let uri = note.textDocument.uri

    let req = sourcekitd.dictionary([
      keys.request: self.requests.editor_close,
      keys.name: uri.pseudoPath,
    ])

    _ = try? await self.sourcekitd.send(req, fileContents: nil)
  }

  /// Cancels any in-flight tasks to send a `PublishedDiagnosticsNotification` after edits.
  private func cancelInFlightPublishDiagnosticsTask(for document: DocumentURI) {
    if let inFlightTask = inFlightPublishDiagnosticsTasks[document] {
      inFlightTask.cancel()
    }
  }

  /// If the client doesn't support pull diagnostics, compute diagnostics for the latest version of the given document
  /// and send a `PublishDiagnosticsNotification` to the client for it.
  private func publishDiagnosticsIfNeeded(for document: DocumentURI) {
    withLoggingScope("publish-diagnostics") {
      publishDiagnosticsIfNeededImpl(for: document)
    }
  }

  private func publishDiagnosticsIfNeededImpl(for document: DocumentURI) {
    guard enablePublishDiagnostics else {
      return
    }
    guard diagnosticsEnabled(for: document) else {
      return
    }
    cancelInFlightPublishDiagnosticsTask(for: document)
    inFlightPublishDiagnosticsTasks[document] = Task(priority: .medium) { [weak self] in
      guard let self, let sourceKitServer = await self.sourceKitServer else {
        logger.fault("Cannot produce PublishDiagnosticsNotification because sourceKitServer was deallocated")
        return
      }
      do {
        // Sleep for a little bit until triggering the diagnostic generation. This effectively de-bounces diagnostic
        // generation since any later edit will cancel the previous in-flight task, which will thus never go on to send
        // the `DocumentDiagnosticsRequest`.
        try await Task.sleep(
          nanoseconds: UInt64(sourceKitServer.options.swiftPublishDiagnosticsDebounceDuration * 1_000_000_000)
        )
      } catch {
        return
      }
      do {
        let snapshot = try await documentManager.latestSnapshot(document)
        let buildSettings = await self.buildSettings(for: document)
        let diagnosticReport = try await self.diagnosticReportManager.diagnosticReport(
          for: snapshot,
          buildSettings: buildSettings
        )

        await sourceKitServer.sendNotificationToClient(
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

  public func changeDocument(_ note: DidChangeTextDocumentNotification) async {
    cancelInFlightPublishDiagnosticsTask(for: note.textDocument.uri)

    let keys = self.keys
    struct Edit {
      let offset: Int
      let length: Int
      let replacement: String
    }

    var edits: [Edit] = []

    let editResult = self.documentManager.edit(note) {
      (before: LineTable, edit: TextDocumentContentChangeEvent) in
      if let range = edit.range {
        guard let offset = before.utf8OffsetOf(line: range.lowerBound.line, utf16Column: range.lowerBound.utf16index),
          let end = before.utf8OffsetOf(line: range.upperBound.line, utf16Column: range.upperBound.utf16index)
        else {
          fatalError("invalid edit \(range)")
        }
        edits.append(
          Edit(
            offset: offset,
            length: end - offset,
            replacement: edit.text
          )
        )
      } else {
        edits.append(
          Edit(
            offset: 0,
            length: before.content.utf8.count,
            replacement: edit.text
          )
        )
      }
    }
    for edit in edits {
      let req = sourcekitd.dictionary([
        keys.request: self.requests.editor_replacetext,
        keys.name: note.textDocument.uri.pseudoPath,
        keys.syntactic_only: 1,
        keys.offset: edit.offset,
        keys.length: edit.length,
        keys.sourcetext: edit.replacement,
      ])
      do {
        _ = try await self.sourcekitd.send(req, fileContents: nil)
      } catch {
        fatalError("failed to apply edit")
      }
    }

    guard let (preEditSnapshot, postEditSnapshot) = editResult else {
      return
    }
    let concurrentEdits = ConcurrentEdits(
      fromSequential: edits.map {
        IncrementalEdit(offset: $0.offset, length: $0.length, replacementLength: $0.replacement.utf8.count)
      }
    )
    await syntaxTreeManager.registerEdit(
      preEditSnapshot: preEditSnapshot,
      postEditSnapshot: postEditSnapshot,
      edits: concurrentEdits
    )

    publishDiagnosticsIfNeeded(for: note.textDocument.uri)
  }

  public func willSaveDocument(_ note: WillSaveTextDocumentNotification) {

  }

  public func didSaveDocument(_ note: DidSaveTextDocumentNotification) {

  }

  // MARK: - Language features

  /// Returns true if the `ToolchainLanguageServer` will take ownership of the request.
  public func definition(_ request: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    throw ResponseError.unknown("unsupported method")
  }

  public func declaration(_ request: DeclarationRequest) async throws -> LocationsOrLocationLinksResponse? {
    throw ResponseError.unknown("unsupported method")
  }

  public func hover(_ req: HoverRequest) async throws -> HoverResponse? {
    let uri = req.textDocument.uri
    let position = req.position
    guard let cursorInfo = try await cursorInfo(uri, position..<position) else {
      return nil
    }

    guard let name: String = cursorInfo.symbolInfo.name else {
      // There is a cursor but we don't know how to deal with it.
      return nil
    }

    /// Prepend backslash to `*` and `_`, to prevent them
    /// from being interpreted as markdown.
    func escapeNameMarkdown(_ str: String) -> String {
      return String(str.flatMap({ ($0 == "*" || $0 == "_") ? ["\\", $0] : [$0] }))
    }

    var result = escapeNameMarkdown(name)
    if let doc = cursorInfo.documentationXML {
      result += """

        \(orLog("Convert XML to Markdown") { try xmlDocumentationToMarkdown(doc) } ?? doc)
        """
    } else if let annotated: String = cursorInfo.annotatedDeclaration {
      result += """

        \(orLog("Convert XML to Markdown") { try xmlDocumentationToMarkdown(annotated) } ?? annotated)
        """
    }

    return HoverResponse(contents: .markupContent(MarkupContent(kind: .markdown, value: result)), range: nil)
  }

  public func documentColor(_ req: DocumentColorRequest) async throws -> [ColorInformation] {
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

        guard let startPosition = snapshot.position(of: node.position),
          let endPosition = snapshot.position(of: node.endPosition)
        else {
          return .skipChildren
        }

        result.append(
          ColorInformation(
            range: startPosition..<endPosition,
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

  public func colorPresentation(_ req: ColorPresentationRequest) async throws -> [ColorPresentation] {
    let color = req.color
    // Empty string as a label breaks VSCode color picker
    let label = "Color Literal"
    let newText = "#colorLiteral(red: \(color.red), green: \(color.green), blue: \(color.blue), alpha: \(color.alpha))"
    let textEdit = TextEdit(range: req.range, newText: newText)
    let presentation = ColorPresentation(label: label, textEdit: textEdit, additionalTextEdits: nil)
    return [presentation]
  }

  public func documentSymbolHighlight(_ req: DocumentHighlightRequest) async throws -> [DocumentHighlight]? {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)

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

  public func codeAction(_ req: CodeActionRequest) async throws -> CodeActionRequestResponse? {
    let providersAndKinds: [(provider: CodeActionProvider, kind: CodeActionKind)] = [
      (retrieveRefactorCodeActions, .refactor),
      (retrieveQuickFixCodeActions, .quickFix),
    ]
    let wantedActionKinds = req.context.only
    let providers = providersAndKinds.filter { wantedActionKinds?.contains($0.1) != false }
    let codeActionCapabilities = capabilityRegistry.clientCapabilities.textDocument?.codeAction
    let codeActions = try await retrieveCodeActions(req, providers: providers.map { $0.provider })
    let response = CodeActionRequestResponse(
      codeActions: codeActions,
      clientCapabilities: codeActionCapabilities
    )
    return response
  }

  func retrieveCodeActions(_ req: CodeActionRequest, providers: [CodeActionProvider]) async throws -> [CodeAction] {
    guard providers.isEmpty == false else {
      return []
    }
    let codeActions = await withTaskGroup(of: [CodeAction].self) { taskGroup in
      for provider in providers {
        taskGroup.addTask {
          do {
            return try await provider(req)
          } catch {
            // Ignore any providers that failed to provide refactoring actions.
            return []
          }
        }
      }
      var results: [CodeAction] = []
      for await taskResults in taskGroup {
        results += taskResults
      }
      return results
    }
    return codeActions
  }

  func retrieveRefactorCodeActions(_ params: CodeActionRequest) async throws -> [CodeAction] {
    let additionalCursorInfoParameters: ((SKDRequestDictionary) -> Void) = { skreq in
      skreq.set(self.keys.retrieve_refactor_actions, to: 1)
    }

    let cursorInfoResponse = try await cursorInfo(
      params.textDocument.uri,
      params.range,
      additionalParameters: additionalCursorInfoParameters
    )

    guard let cursorInfoResponse else {
      throw ResponseError.unknown("CursorInfo failed.")
    }
    guard let refactorActions = cursorInfoResponse.refactorActions else {
      return []
    }
    let codeActions: [CodeAction] = refactorActions.compactMap {
      do {
        let lspCommand = try $0.asCommand()
        return CodeAction(title: $0.title, kind: .refactor, command: lspCommand)
      } catch {
        logger.log("Failed to convert SwiftCommand to Command type: \(error.forLogging)")
        return nil
      }
    }
    return codeActions
  }

  func retrieveQuickFixCodeActions(_ params: CodeActionRequest) async throws -> [CodeAction] {
    let snapshot = try documentManager.latestSnapshot(params.textDocument.uri)
    let buildSettings = await self.buildSettings(for: params.textDocument.uri)
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

  public func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
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

  public func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport {
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    let buildSettings = await self.buildSettings(for: req.textDocument.uri)
    let diagnosticReport = try await self.diagnosticReportManager.diagnosticReport(
      for: snapshot,
      buildSettings: buildSettings
    )
    do {
      return try await .full(diagnosticReport)
    } catch {
      // VS Code does not request diagnostics again for a document if the diagnostics request failed.
      // Since sourcekit-lsp usually recovers from failures (e.g. after sourcekitd crashes), this is undesirable.
      // Instead of returning an error, return empty results.
      logger.error(
        """
        Loading diagnostic failed with the following error. Returning empty diagnostics. 
        \(error.forLogging)
        """
      )
      return .full(RelatedFullDocumentDiagnosticReport(items: []))
    }
  }

  public func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny? {
    // TODO: If there's support for several types of commands, we might need to structure this similarly to the code actions request.
    guard let sourceKitServer else {
      // `SourceKitServer` has been destructed. We are tearing down the language
      // server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }
    guard let swiftCommand = req.swiftCommand(ofType: SemanticRefactorCommand.self) else {
      throw ResponseError.unknown("semantic refactoring: unknown command \(req.command)")
    }
    let refactor = try await semanticRefactoring(swiftCommand)
    let edit = refactor.edit
    let req = ApplyEditRequest(label: refactor.title, edit: edit)
    let response = try await sourceKitServer.sendRequestToClient(req)
    if !response.applied {
      let reason: String
      if let failureReason = response.failureReason {
        reason = " reason: \(failureReason)"
      } else {
        reason = ""
      }
      logger.error("client refused to apply edit for \(refactor.title, privacy: .public)!\(reason)")
    }
    return edit.encodeToLSPAny()
  }
}

extension SwiftLanguageServer: SKDNotificationHandler {
  public nonisolated func notification(_ notification: SKDResponse) {
    sourcekitdNotificationHandlingQueue.async {
      await self.notificationImpl(notification)
    }
  }

  private func notificationImpl(_ notification: SKDResponse) async {
    // Check if we need to update our `state` based on the contents of the notification.
    if notification.value?[self.keys.notification] == self.values.notification_sema_enabled {
      self.state = .connected
    }

    if self.state == .connectionInterrupted {
      // If we get a notification while we are restoring the connection, it means that the server has restarted.
      // We still need to wait for semantic functionality to come back up.
      self.state = .semanticFunctionalityDisabled

      // Ask our parent to re-open all of our documents.
      if let sourceKitServer {
        await sourceKitServer.reopenDocuments(for: self)
      } else {
        logger.fault("Cannot reopen documents because SourceKitServer is no longer alive")
      }
    }

    if notification.error == .connectionInterrupted {
      self.state = .connectionInterrupted

      // We don't have any open documents anymore after sourcekitd crashed.
      // Reset the document manager to reflect that.
      self.documentManager = DocumentManager()
    }

    logger.debug(
      """
      Received notification from sourcekitd
      \(notification.forLogging)
      """
    )
  }
}

extension DocumentSnapshot {

  func utf8Offset(of pos: Position) -> Int? {
    return lineTable.utf8OffsetOf(line: pos.line, utf16Column: pos.utf16index)
  }

  func utf8OffsetRange(of range: Range<Position>) -> Range<Int>? {
    guard let startOffset = utf8Offset(of: range.lowerBound),
      let endOffset = utf8Offset(of: range.upperBound)
    else {
      return nil
    }
    return startOffset..<endOffset
  }

  func positionOf(utf8Offset: Int) -> Position? {
    return lineTable.lineAndUTF16ColumnOf(utf8Offset: utf8Offset).map {
      Position(line: $0.line, utf16index: $0.utf16Column)
    }
  }

  func positionOf(zeroBasedLine: Int, utf8Column: Int) -> Position? {
    return lineTable.utf16ColumnAt(line: zeroBasedLine, utf8Column: utf8Column).map {
      Position(line: zeroBasedLine, utf16index: $0)
    }
  }

  func position(of position: AbsolutePosition) -> Position? {
    return positionOf(utf8Offset: position.utf8Offset)
  }

  func range(of range: Range<AbsolutePosition>) -> Range<Position>? {
    guard let lowerBound = self.position(of: range.lowerBound),
      let upperBound = self.position(of: range.upperBound)
    else {
      return nil
    }
    return lowerBound..<upperBound
  }

  func position(of position: Position) -> AbsolutePosition? {
    guard let offset = utf8Offset(of: position) else {
      return nil
    }
    return AbsolutePosition(utf8Offset: offset)
  }

  func indexOf(utf8Offset: Int) -> String.Index? {
    return text.utf8.index(text.startIndex, offsetBy: utf8Offset, limitedBy: text.endIndex)
  }
}

extension sourcekitd_uid_t {
  func isCommentKind(_ vals: sourcekitd_values) -> Bool {
    switch self {
    case vals.syntaxtype_comment, vals.syntaxtype_comment_marker, vals.syntaxtype_comment_url:
      return true
    default:
      return isDocCommentKind(vals)
    }
  }

  func isDocCommentKind(_ vals: sourcekitd_values) -> Bool {
    return self == vals.syntaxtype_doccomment || self == vals.syntaxtype_doccomment_field
  }

  func asCompletionItemKind(_ vals: sourcekitd_values) -> CompletionItemKind? {
    switch self {
    case vals.kind_keyword:
      return .keyword
    case vals.decl_module:
      return .module
    case vals.decl_class:
      return .class
    case vals.decl_struct:
      return .struct
    case vals.decl_enum:
      return .enum
    case vals.decl_enumelement:
      return .enumMember
    case vals.decl_protocol:
      return .interface
    case vals.decl_associatedtype:
      return .typeParameter
    case vals.decl_typealias:
      return .typeParameter  // FIXME: is there a better choice?
    case vals.decl_generic_type_param:
      return .typeParameter
    case vals.decl_function_constructor:
      return .constructor
    case vals.decl_function_destructor:
      return .value  // FIXME: is there a better choice?
    case vals.decl_function_subscript:
      return .method  // FIXME: is there a better choice?
    case vals.decl_function_method_static:
      return .method
    case vals.decl_function_method_instance:
      return .method
    case vals.decl_function_operator_prefix,
      vals.decl_function_operator_postfix,
      vals.decl_function_operator_infix:
      return .operator
    case vals.decl_precedencegroup:
      return .value
    case vals.decl_function_free:
      return .function
    case vals.decl_var_static, vals.decl_var_class:
      return .property
    case vals.decl_var_instance:
      return .property
    case vals.decl_var_local,
      vals.decl_var_global,
      vals.decl_var_parameter:
      return .variable
    default:
      return nil
    }
  }

  func asSymbolKind(_ vals: sourcekitd_values) -> SymbolKind? {
    switch self {
    case vals.decl_class:
      return .class
    case vals.decl_function_method_instance,
      vals.decl_function_method_static,
      vals.decl_function_method_class:
      return .method
    case vals.decl_var_instance,
      vals.decl_var_static,
      vals.decl_var_class:
      return .property
    case vals.decl_enum:
      return .enum
    case vals.decl_enumelement:
      return .enumMember
    case vals.decl_protocol:
      return .interface
    case vals.decl_function_free:
      return .function
    case vals.decl_var_global,
      vals.decl_var_local:
      return .variable
    case vals.decl_struct:
      return .struct
    case vals.decl_generic_type_param:
      return .typeParameter
    case vals.decl_extension:
      // There are no extensions in LSP, so I return something vaguely similar
      return .namespace
    case vals.ref_module:
      return .module
    default:
      return nil
    }
  }
}
