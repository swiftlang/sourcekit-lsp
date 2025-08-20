//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
package import IndexStoreDB
package import LanguageServerProtocol
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
package import SwiftSyntax
package import ToolchainRegistry

package actor DocumentationLanguageService: LanguageService, Sendable {
  /// The ``SourceKitLSPServer`` instance that created this `DocumentationLanguageService`.
  private(set) weak var sourceKitLSPServer: SourceKitLSPServer?

  var documentManager: DocumentManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentManager
    }
  }

  package static var builtInCommands: [String] { [] }

  package init?(
    sourceKitLSPServer: SourceKitLSPServer,
    toolchain: Toolchain,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    workspace: Workspace
  ) async throws {
    self.sourceKitLSPServer = sourceKitLSPServer
  }

  func workspaceForDocument(uri: DocumentURI) async throws -> Workspace? {
    guard let sourceKitLSPServer else {
      throw ResponseError.unknown("Connection to the editor closed")
    }
    return await sourceKitLSPServer.workspaceForDocument(uri: uri)
  }

  package nonisolated func canHandle(workspace: Workspace, toolchain: Toolchain) -> Bool {
    return true
  }

  package func initialize(
    _ initialize: InitializeRequest
  ) async throws -> InitializeResult {
    return InitializeResult(
      capabilities: ServerCapabilities()
    )
  }

  package func clientInitialized(_ initialized: InitializedNotification) async {
    // Nothing to set up
  }

  package func shutdown() async {
    // Nothing to tear down
  }

  package func addStateChangeHandler(
    handler: @escaping @Sendable (LanguageServerState, LanguageServerState) -> Void
  ) async {
    // There is no underlying language server with which to report state
  }

  package func openDocument(
    _ notification: DidOpenTextDocumentNotification,
    snapshot: DocumentSnapshot
  ) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func closeDocument(_ notification: DidCloseTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func reopenDocument(_ notification: ReopenTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func changeDocument(
    _ notification: DidChangeTextDocumentNotification,
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot,
    edits: [SwiftSyntax.SourceEdit]
  ) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func willSaveDocument(_ notification: WillSaveTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func didSaveDocument(_ notification: DidSaveTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func documentUpdatedBuildSettings(_ uri: DocumentURI) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func documentDependenciesUpdated(_ uris: Set<DocumentURI>) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func completion(_ req: CompletionRequest) async throws -> CompletionList {
    CompletionList(isIncomplete: false, items: [])
  }

  package func completionItemResolve(_ req: CompletionItemResolveRequest) async throws -> CompletionItem {
    return req.item
  }

  package func hover(_ req: HoverRequest) async throws -> HoverResponse? {
    nil
  }

  package func symbolInfo(_ request: SymbolInfoRequest) async throws -> [SymbolDetails] {
    []
  }

  package func symbolGraph(
    forOnDiskContentsOf symbolDocumentUri: DocumentURI,
    at location: SymbolLocation
  ) async throws -> String {
    throw ResponseError.internalError("Not applicable")
  }

  package func symbolGraph(
    for snapshot: SourceKitLSP.DocumentSnapshot,
    at position: LanguageServerProtocol.Position
  ) async throws -> (symbolGraph: String, usr: String, overrideDocComments: [String]) {
    throw ResponseError.internalError("Not applicable")
  }

  package func openGeneratedInterface(
    document: DocumentURI,
    moduleName: String,
    groupName: String?,
    symbolUSR symbol: String?
  ) async throws -> GeneratedInterfaceDetails? {
    nil
  }

  package func definition(_ request: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    nil
  }

  package func declaration(_ request: DeclarationRequest) async throws -> LocationsOrLocationLinksResponse? {
    nil
  }

  package func documentSymbolHighlight(_ req: DocumentHighlightRequest) async throws -> [DocumentHighlight]? {
    nil
  }

  package func foldingRange(_ req: FoldingRangeRequest) async throws -> [FoldingRange]? {
    nil
  }

  package func documentSymbol(_ req: DocumentSymbolRequest) async throws -> DocumentSymbolResponse? {
    nil
  }

  package func documentColor(_ req: DocumentColorRequest) async throws -> [ColorInformation] {
    []
  }

  package func documentSemanticTokens(
    _ req: DocumentSemanticTokensRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    nil
  }

  package func documentSemanticTokensDelta(
    _ req: DocumentSemanticTokensDeltaRequest
  ) async throws -> DocumentSemanticTokensDeltaResponse? {
    nil
  }

  package func documentSemanticTokensRange(
    _ req: DocumentSemanticTokensRangeRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    nil
  }

  package func colorPresentation(_ req: ColorPresentationRequest) async throws -> [ColorPresentation] {
    []
  }

  package func codeAction(_ req: CodeActionRequest) async throws -> CodeActionRequestResponse? {
    nil
  }

  package func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
    []
  }

  package func codeLens(_ req: CodeLensRequest) async throws -> [CodeLens] {
    []
  }

  package func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport {
    .full(RelatedFullDocumentDiagnosticReport(items: []))
  }

  package func documentFormatting(_ req: DocumentFormattingRequest) async throws -> [TextEdit]? {
    nil
  }

  package func documentRangeFormatting(
    _ req: LanguageServerProtocol.DocumentRangeFormattingRequest
  ) async throws -> [LanguageServerProtocol.TextEdit]? {
    return nil
  }

  package func documentOnTypeFormatting(_ req: DocumentOnTypeFormattingRequest) async throws -> [TextEdit]? {
    return nil
  }

  package func rename(_ request: RenameRequest) async throws -> (edits: WorkspaceEdit, usr: String?) {
    (edits: WorkspaceEdit(), usr: nil)
  }

  package func editsToRename(
    locations renameLocations: [RenameLocation],
    in snapshot: DocumentSnapshot,
    oldName: CrossLanguageName,
    newName: CrossLanguageName
  ) async throws -> [TextEdit] {
    []
  }

  package func prepareRename(
    _ request: PrepareRenameRequest
  ) async throws -> (prepareRename: PrepareRenameResponse, usr: String?)? {
    nil
  }

  package func indexedRename(_ request: IndexedRenameRequest) async throws -> WorkspaceEdit? {
    nil
  }

  package func editsToRenameParametersInFunctionBody(
    snapshot: DocumentSnapshot,
    renameLocation: RenameLocation,
    newName: CrossLanguageName
  ) async -> [TextEdit] {
    []
  }

  package func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny? {
    nil
  }

  package func getReferenceDocument(_ req: GetReferenceDocumentRequest) async throws -> GetReferenceDocumentResponse {
    GetReferenceDocumentResponse(content: "")
  }

  package func syntacticDocumentTests(
    for uri: DocumentURI,
    in workspace: Workspace
  ) async throws -> [AnnotatedTestItem]? {
    nil
  }

  package static func syntacticTestItems(in uri: DocumentURI) async -> [AnnotatedTestItem] {
    return []
  }

  package func canonicalDeclarationPosition(
    of position: Position,
    in uri: DocumentURI
  ) async -> Position? {
    nil
  }

  package func crash() async {
    // There's no way to crash the DocumentationLanguageService
  }
}
