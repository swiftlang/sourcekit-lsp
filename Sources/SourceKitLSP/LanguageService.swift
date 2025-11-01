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

package import BuildServerIntegration
import Foundation
package import IndexStoreDB
package import LanguageServerProtocol
import SKLogging
package import SKOptions
package import SwiftSyntax
package import ToolchainRegistry

/// The state of a `ToolchainLanguageServer`
package enum LanguageServerState {
  /// The language server is running with semantic functionality enabled
  case connected
  /// The language server server has crashed and we are waiting for it to relaunch
  case connectionInterrupted
  /// The language server has relaunched but semantic functionality is currently disabled
  case semanticFunctionalityDisabled
}

package struct AnnotatedTestItem: Sendable {
  /// The test item to be annotated
  package var testItem: TestItem

  /// Whether the `TestItem` is an extension.
  package var isExtension: Bool

  package init(
    testItem: TestItem,
    isExtension: Bool
  ) {
    self.testItem = testItem
    self.isExtension = isExtension
  }
}

package struct RenameLocation: Sendable {
  /// How the identifier at a given location is being used.
  ///
  /// This is primarily used to influence how argument labels should be renamed in Swift and if a location should be
  /// rejected if argument labels don't match.
  package enum Usage {
    /// The definition of a function/subscript/variable/...
    case definition

    /// The symbol is being referenced.
    ///
    /// This includes
    ///  - References to variables
    ///  - Unapplied references to functions (`myStruct.memberFunc`)
    ///  - Calls to subscripts (`myArray[1]`, location is `[` here, length 1)
    case reference

    /// A function that is being called.
    case call

    /// Unknown name usage occurs if we don't have an entry in the index that
    /// tells us whether the location is a call, reference or a definition. The
    /// most common reasons why this happens is if the editor is adding syntactic
    /// results (eg. from comments or string literals).
    case unknown
  }

  /// The line of the identifier to be renamed (1-based).
  package let line: Int

  /// The column of the identifier to be renamed in UTF-8 bytes (1-based).
  package let utf8Column: Int

  package let usage: Usage

  package init(line: Int, utf8Column: Int, usage: RenameLocation.Usage) {
    self.line = line
    self.utf8Column = utf8Column
    self.usage = usage
  }
}

/// The textual output of a module interface.
package struct GeneratedInterfaceDetails: ResponseType, Hashable {
  package var uri: DocumentURI
  package var position: Position?

  package init(uri: DocumentURI, position: Position?) {
    self.uri = uri
    self.position = position
  }
}

/// Provides language specific functionality to sourcekit-lsp from a specific toolchain.
///
/// For example, we may have a language service that provides semantic functionality for c-family using a clangd server,
/// launched from a specific toolchain or from sourcekitd.
package protocol LanguageService: AnyObject, Sendable {

  // MARK: - Creation

  init(
    sourceKitLSPServer: SourceKitLSPServer,
    toolchain: Toolchain,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    workspace: Workspace
  ) async throws

  /// Returns `true` if this instance of the language server can handle documents in `workspace` using the given
  /// toolchain.
  ///
  /// If this returns `false`, a new language server will be started for `workspace`.
  func canHandle(workspace: Workspace, toolchain: Toolchain) -> Bool

  /// Identifiers of the commands that this language service can handle.
  static var builtInCommands: [String] { get }

  /// Experimental capabilities that should be reported to the client if this language service is enabled.
  static var experimentalCapabilities: [String: LSPAny] { get }

  // MARK: - Lifetime

  func initialize(_ initialize: InitializeRequest) async throws -> InitializeResult
  func clientInitialized(_ initialized: InitializedNotification) async

  /// Shut the server down and return once the server has finished shutting down
  func shutdown() async

  /// Add a handler that is called whenever the state of the language server changes.
  func addStateChangeHandler(
    handler: @Sendable @escaping (_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void
  ) async

  // MARK: - Text synchronization

  /// Sent to open up a document on the Language Server.
  ///
  /// This may be called before or after a corresponding `documentUpdatedBuildSettings` call for the same document.
  func openDocument(_ notification: DidOpenTextDocumentNotification, snapshot: DocumentSnapshot) async

  /// Sent to close a document on the Language Server.
  func closeDocument(_ notification: DidCloseTextDocumentNotification) async

  /// Sent to open up a document on the Language Server whose contents are on-disk.
  ///
  /// The snapshot will have a synthesized name and the caller is responsible for synthesizing build settings for it.
  ///
  /// - Important: This should only be called by `OnDiskDocumentManager`.
  func openOnDiskDocument(snapshot: DocumentSnapshot, buildSettings: FileBuildSettings) async throws

  /// Sent to close a document that was opened by `openOnDiskDocument`.
  ///
  /// - Important: This should only be called by `OnDiskDocumentManager`.
  func closeOnDiskDocument(uri: DocumentURI) async throws

  /// Re-open the given document, discarding any in-memory state and forcing an AST to be re-built after build settings
  /// have been changed. This needs to be handled via a notification to ensure that no other request for this document
  /// is executing at the same time.
  ///
  /// Only intended for `SwiftLanguageService`.
  func reopenDocument(_ notification: ReopenTextDocumentNotification) async

  func changeDocument(
    _ notification: DidChangeTextDocumentNotification,
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot,
    edits: [SourceEdit]
  ) async
  func willSaveDocument(_ notification: WillSaveTextDocumentNotification) async
  func didSaveDocument(_ notification: DidSaveTextDocumentNotification) async

  /// Called when files are changed on disk and the editor sends a `workspace/didChangeWatchedFiles` notification to
  /// SourceKit-LSP.
  func filesDidChange(_ events: [FileEvent]) async

  // MARK: - Build Server Integration

  /// Sent when the build server has resolved build settings, such as for the initial build settings
  /// or when the settings have changed (e.g. modified build server files). This may be sent before
  /// the respective `DocumentURI` has been opened.
  func documentUpdatedBuildSettings(_ uri: DocumentURI) async

  /// Sent when the build server has detected that dependencies of the given files have changed
  /// (e.g. header files, swiftmodule files, other compiler input files).
  func documentDependenciesUpdated(_ uris: Set<DocumentURI>) async

  // MARK: - Text Document

  func completion(_ req: CompletionRequest) async throws -> CompletionList
  func completionItemResolve(_ req: CompletionItemResolveRequest) async throws -> CompletionItem
  func signatureHelp(_ req: SignatureHelpRequest) async throws -> SignatureHelp?
  func hover(_ req: HoverRequest) async throws -> HoverResponse?
  func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse
  func symbolInfo(_ request: SymbolInfoRequest) async throws -> [SymbolDetails]

  /// Retrieve the symbol graph for the given position in the given snapshot, including the USR of the symbol at the
  /// given position and the doc comments of the symbol at that position.
  func symbolGraph(
    for snapshot: DocumentSnapshot,
    at position: Position
  ) async throws -> (symbolGraph: String, usr: String, overrideDocComments: [String])

  /// Return the symbol graph at the given location for the contents of the document as they are on-disk (opposed to the
  /// in-memory modified version of the document).
  func symbolGraph(
    forOnDiskContentsAt location: SymbolLocation,
    in workspace: Workspace,
    manager: OnDiskDocumentManager
  ) async throws -> String

  /// Request a generated interface of a module to display in the IDE.
  ///
  /// - Parameters:
  ///   - document: The document whose compiler arguments should be used to generate the interface.
  ///   - moduleName: The module to generate an index for.
  ///   - groupName: The module group name.
  ///   - symbol: The symbol USR to search for in the generated module interface.
  func openGeneratedInterface(
    document: DocumentURI,
    moduleName: String,
    groupName: String?,
    symbolUSR symbol: String?
  ) async throws -> GeneratedInterfaceDetails?

  /// - Note: Only called as a fallback if the definition could not be found in the index.
  func definition(_ request: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse?

  func declaration(_ request: DeclarationRequest) async throws -> LocationsOrLocationLinksResponse?
  func documentSymbolHighlight(_ req: DocumentHighlightRequest) async throws -> [DocumentHighlight]?
  func foldingRange(_ req: FoldingRangeRequest) async throws -> [FoldingRange]?
  func documentSymbol(_ req: DocumentSymbolRequest) async throws -> DocumentSymbolResponse?
  func documentColor(_ req: DocumentColorRequest) async throws -> [ColorInformation]
  func documentSemanticTokens(_ req: DocumentSemanticTokensRequest) async throws -> DocumentSemanticTokensResponse?
  func documentSemanticTokensDelta(
    _ req: DocumentSemanticTokensDeltaRequest
  ) async throws -> DocumentSemanticTokensDeltaResponse?
  func documentSemanticTokensRange(
    _ req: DocumentSemanticTokensRangeRequest
  ) async throws -> DocumentSemanticTokensResponse?
  func colorPresentation(_ req: ColorPresentationRequest) async throws -> [ColorPresentation]
  func codeAction(_ req: CodeActionRequest) async throws -> CodeActionRequestResponse?
  func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint]
  func codeLens(_ req: CodeLensRequest) async throws -> [CodeLens]
  func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport
  func documentFormatting(_ req: DocumentFormattingRequest) async throws -> [TextEdit]?
  func documentRangeFormatting(_ req: DocumentRangeFormattingRequest) async throws -> [TextEdit]?
  func documentOnTypeFormatting(_ req: DocumentOnTypeFormattingRequest) async throws -> [TextEdit]?

  // MARK: - Rename

  /// Entry point to perform rename.
  ///
  /// Rename is implemented as a two-step process:  This function returns all the edits it knows need to be performed.
  /// For Swift these edits are those within the current file. In addition, it can return a USR + the old name of the
  /// symbol to be renamed so that `SourceKitLSPServer` can perform an index lookup to discover more locations to rename
  /// within the entire workspace. `SourceKitLSPServer` will transform those into edits by calling
  /// `editsToRename(locations:in:oldName:newName:)` on the toolchain server to perform the actual rename.
  func rename(_ request: RenameRequest) async throws -> (edits: WorkspaceEdit, usr: String?)

  /// Given a list of `locations``, return the list of edits that need to be performed to rename these occurrences from
  /// `oldName` to `newName`.
  func editsToRename(
    locations renameLocations: [RenameLocation],
    in snapshot: DocumentSnapshot,
    oldName: CrossLanguageName,
    newName: CrossLanguageName
  ) async throws -> [TextEdit]

  /// Return compound decl name that will be used as a placeholder for a rename request at a specific position.
  func prepareRename(
    _ request: PrepareRenameRequest
  ) async throws -> (prepareRename: PrepareRenameResponse, usr: String?)?

  func indexedRename(_ request: IndexedRenameRequest) async throws -> WorkspaceEdit?

  /// If there is a function-like definition at the given `renamePosition`, rename all the references to parameters
  /// inside the function's body.
  ///
  /// For example, this produces the edit to rename the occurrence of `x` inside `print` in the following
  ///
  /// ```swift
  /// func foo(x: Int) { print(x) }
  /// ```
  ///
  /// - Parameters:
  ///   - snapshot: A `DocumentSnapshot` containing the file contents
  ///   - renameLocation: The position of the function's base name (in front of `foo` in the above example)
  ///   - newName: The new name of the function (eg. `bar(y:)` in the above example)
  func editsToRenameParametersInFunctionBody(
    snapshot: DocumentSnapshot,
    renameLocation: RenameLocation,
    newName: CrossLanguageName
  ) async -> [TextEdit]

  // MARK: - Other

  func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny?

  func getReferenceDocument(_ req: GetReferenceDocumentRequest) async throws -> GetReferenceDocumentResponse

  /// Perform a syntactic scan of the file at the given URI for test cases and test classes.
  ///
  /// This is used as a fallback to show the test cases in a file if the index for a given file is not up-to-date.
  ///
  /// A return value of `nil` indicates that this language service does not support syntactic test discovery.
  func syntacticDocumentTests(for uri: DocumentURI, in workspace: Workspace) async throws -> [AnnotatedTestItem]?

  /// Syntactically scans the file at the given URL for tests declared within it.
  ///
  /// Does not write the results to the index.
  ///
  /// The order of the returned tests is not defined. The results should be sorted before being returned to the editor.
  static func syntacticTestItems(in uri: DocumentURI) async -> [AnnotatedTestItem]

  /// Syntactically scans the file at the given URL for #Playground macro expansions within it.
  ///
  /// Does not write the results to the index.
  func syntacticDocumentPlaygrounds(for uri: DocumentURI, in workspace: Workspace) async throws -> [PlaygroundItem]

  /// A position that is canonical for all positions within a declaration. For example, if we have the following
  /// declaration, then all `|` markers should return the same canonical position.
  /// ```
  /// func |fo|o(|ba|r: Int)
  /// ```
  /// The actual position returned by the method does not matter. All that's relevant is the canonicalization.
  ///
  /// Returns `nil` if no canonical position could be determined.
  func canonicalDeclarationPosition(of position: Position, in uri: DocumentURI) async -> Position?

  /// Crash the language server. Should be used for crash recovery testing only.
  func crash() async
}

/// Default implementations for methods that satisfy the following criteria:
///  - `SourceKitLSPServer` does not expect side effects to happen when they are called
///  - The method can throw or there is a reasonable default value
///  - It is reasonable to expect that not all language services need to implement it
package extension LanguageService {
  static var builtInCommands: [String] { [] }

  static var experimentalCapabilities: [String: LSPAny] { [:] }

  func clientInitialized(_ initialized: InitializedNotification) async {}

  func openOnDiskDocument(snapshot: DocumentSnapshot, buildSettings: FileBuildSettings) async throws {
    throw ResponseError.unknown("\(#function) not implemented in \(Self.self) for \(snapshot.uri)")
  }

  func closeOnDiskDocument(uri: DocumentURI) async throws {
    throw ResponseError.unknown("\(#function) not implemented in \(Self.self) for \(uri)")
  }

  func willSaveDocument(_ notification: WillSaveTextDocumentNotification) async {}

  func didSaveDocument(_ notification: DidSaveTextDocumentNotification) async {}

  func filesDidChange(_ events: [FileEvent]) async {}

  func documentUpdatedBuildSettings(_ uri: DocumentURI) async {}

  func documentDependenciesUpdated(_ uris: Set<DocumentURI>) async {}

  func completion(_ req: CompletionRequest) async throws -> CompletionList {
    throw ResponseError.requestNotImplemented(CompletionRequest.self)
  }

  func completionItemResolve(_ req: CompletionItemResolveRequest) async throws -> CompletionItem {
    throw ResponseError.requestNotImplemented(CompletionItemResolveRequest.self)
  }

  func signatureHelp(_ req: SignatureHelpRequest) async throws -> SignatureHelp? {
    throw ResponseError.requestNotImplemented(SignatureHelpRequest.self)
  }

  func hover(_ req: HoverRequest) async throws -> HoverResponse? {
    throw ResponseError.requestNotImplemented(HoverRequest.self)
  }

  func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    throw ResponseError.requestNotImplemented(DoccDocumentationRequest.self)
  }

  func symbolInfo(_ request: SymbolInfoRequest) async throws -> [SymbolDetails] {
    throw ResponseError.requestNotImplemented(SymbolInfoRequest.self)
  }

  func symbolGraph(
    for snapshot: DocumentSnapshot,
    at position: Position
  ) async throws -> (symbolGraph: String, usr: String, overrideDocComments: [String]) {
    throw ResponseError.internalError("\(#function) not implemented in \(Self.self) for \(snapshot.uri)")
  }

  func symbolGraph(
    forOnDiskContentsAt location: SymbolLocation,
    in workspace: Workspace,
    manager: OnDiskDocumentManager
  ) async throws -> String {
    throw ResponseError.internalError("\(#function) not implemented in \(Self.self) for \(location.path)")
  }

  func openGeneratedInterface(
    document: DocumentURI,
    moduleName: String,
    groupName: String?,
    symbolUSR symbol: String?
  ) async throws -> GeneratedInterfaceDetails? {
    throw ResponseError.internalError("Generated interface not implemented in \(Self.self) for \(document)")
  }

  func definition(_ request: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    throw ResponseError.requestNotImplemented(DefinitionRequest.self)
  }

  func declaration(_ request: DeclarationRequest) async throws -> LocationsOrLocationLinksResponse? {
    throw ResponseError.requestNotImplemented(DeclarationRequest.self)
  }

  func documentSymbolHighlight(_ req: DocumentHighlightRequest) async throws -> [DocumentHighlight]? {
    throw ResponseError.requestNotImplemented(DocumentHighlightRequest.self)
  }

  func foldingRange(_ req: FoldingRangeRequest) async throws -> [FoldingRange]? {
    throw ResponseError.requestNotImplemented(FoldingRangeRequest.self)
  }

  func documentSymbol(_ req: DocumentSymbolRequest) async throws -> DocumentSymbolResponse? {
    throw ResponseError.requestNotImplemented(DocumentSymbolRequest.self)
  }

  func documentColor(_ req: DocumentColorRequest) async throws -> [ColorInformation] {
    throw ResponseError.requestNotImplemented(DocumentColorRequest.self)
  }

  func documentSemanticTokens(_ req: DocumentSemanticTokensRequest) async throws -> DocumentSemanticTokensResponse? {
    throw ResponseError.requestNotImplemented(DocumentSemanticTokensRequest.self)
  }

  func documentSemanticTokensDelta(
    _ req: DocumentSemanticTokensDeltaRequest
  ) async throws -> DocumentSemanticTokensDeltaResponse? {
    throw ResponseError.requestNotImplemented(DocumentSemanticTokensDeltaRequest.self)
  }

  func documentSemanticTokensRange(
    _ req: DocumentSemanticTokensRangeRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    throw ResponseError.requestNotImplemented(DocumentSemanticTokensRangeRequest.self)
  }

  func colorPresentation(_ req: ColorPresentationRequest) async throws -> [ColorPresentation] {
    throw ResponseError.requestNotImplemented(ColorPresentationRequest.self)
  }

  func codeAction(_ req: CodeActionRequest) async throws -> CodeActionRequestResponse? {
    throw ResponseError.requestNotImplemented(CodeActionRequest.self)
  }

  func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
    throw ResponseError.requestNotImplemented(InlayHintRequest.self)
  }

  func codeLens(_ req: CodeLensRequest) async throws -> [CodeLens] {
    throw ResponseError.requestNotImplemented(CodeLensRequest.self)
  }

  func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport {
    throw ResponseError.requestNotImplemented(DocumentDiagnosticsRequest.self)
  }

  func documentFormatting(_ req: DocumentFormattingRequest) async throws -> [TextEdit]? {
    throw ResponseError.requestNotImplemented(DocumentFormattingRequest.self)
  }

  func documentRangeFormatting(_ req: DocumentRangeFormattingRequest) async throws -> [TextEdit]? {
    throw ResponseError.requestNotImplemented(DocumentRangeFormattingRequest.self)
  }

  func documentOnTypeFormatting(_ req: DocumentOnTypeFormattingRequest) async throws -> [TextEdit]? {
    throw ResponseError.requestNotImplemented(DocumentOnTypeFormattingRequest.self)
  }

  func rename(_ request: RenameRequest) async throws -> (edits: WorkspaceEdit, usr: String?) {
    throw ResponseError.requestNotImplemented(RenameRequest.self)
  }

  func editsToRename(
    locations renameLocations: [RenameLocation],
    in snapshot: DocumentSnapshot,
    oldName: CrossLanguageName,
    newName: CrossLanguageName
  ) async throws -> [TextEdit] {
    throw ResponseError.internalError("\(#function) not implemented in \(Self.self) for \(snapshot.uri)")
  }

  func prepareRename(
    _ request: PrepareRenameRequest
  ) async throws -> (prepareRename: PrepareRenameResponse, usr: String?)? {
    throw ResponseError.requestNotImplemented(PrepareRenameRequest.self)
  }

  func indexedRename(_ request: IndexedRenameRequest) async throws -> WorkspaceEdit? {
    throw ResponseError.requestNotImplemented(IndexedRenameRequest.self)
  }

  func editsToRenameParametersInFunctionBody(
    snapshot: DocumentSnapshot,
    renameLocation: RenameLocation,
    newName: CrossLanguageName
  ) async -> [TextEdit] {
    logger.error("\(#function) not implemented in \(Self.self) for \(snapshot.uri)")
    return []
  }

  func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny? {
    throw ResponseError.requestNotImplemented(ExecuteCommandRequest.self)
  }

  func getReferenceDocument(_ req: GetReferenceDocumentRequest) async throws -> GetReferenceDocumentResponse {
    throw ResponseError.requestNotImplemented(GetReferenceDocumentRequest.self)
  }

  func syntacticDocumentTests(for uri: DocumentURI, in workspace: Workspace) async throws -> [AnnotatedTestItem]? {
    throw ResponseError.internalError("syntacticDocumentTests not implemented in \(Self.self) for \(uri)")
  }

  func syntacticDocumentPlaygrounds(for uri: DocumentURI, in workspace: Workspace) async throws -> [PlaygroundItem] {
    throw ResponseError.requestNotImplemented(DocumentPlaygroundsRequest.self)
  }

  func canonicalDeclarationPosition(of position: Position, in uri: DocumentURI) async -> Position? {
    logger.error("\(#function) not implemented in \(Self.self) for \(uri)")
    return nil
  }

  func crash() async {
    logger.error("\(Self.self) cannot be crashed")
  }
}
