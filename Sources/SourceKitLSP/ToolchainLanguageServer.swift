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
import SKCore

/// The state of a `ToolchainLanguageServer`
public enum LanguageServerState {
  /// The language server is running with semantic functionality enabled
  case connected
  /// The language server server has crashed and we are waiting for it to relaunch
  case connectionInterrupted
  /// The language server has relaunched but semantic functionality is currently disabled
  case semanticFunctionalityDisabled
}

public struct RenameLocation {
  /// How the identifier at a given location is being used.
  ///
  /// This is primarily used to influence how argument labels should be renamed in Swift and if a location should be
  /// rejected if argument labels don't match.
  enum Usage {
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
  let line: Int

  /// The column of the identifier to be renamed in UTF-8 bytes (1-based).
  let utf8Column: Int

  let usage: Usage
}

/// A `LanguageServer` that exists within the context of the current process.
public protocol ToolchainLanguageServer: AnyObject {

  // MARK: - Creation

  init?(
    sourceKitServer: SourceKitServer,
    toolchain: Toolchain,
    options: SourceKitServer.Options,
    workspace: Workspace
  ) async throws

  /// Returns `true` if this instance of the language server can handle opening documents in `workspace`.
  ///
  /// If this returns `false`, a new language server will be started for `workspace`.
  func canHandle(workspace: Workspace) -> Bool

  // MARK: - Lifetime

  func initialize(_ initialize: InitializeRequest) async throws -> InitializeResult
  func clientInitialized(_ initialized: InitializedNotification) async

  /// Shut the server down and return once the server has finished shutting down
  func shutdown() async

  /// Add a handler that is called whenever the state of the language server changes.
  func addStateChangeHandler(
    handler: @escaping (_ oldState: LanguageServerState, _ newState: LanguageServerState) -> Void
  ) async

  // MARK: - Text synchronization

  /// Sent to open up a document on the Language Server.
  /// This may be called before or after a corresponding
  /// `documentUpdatedBuildSettings` call for the same document.
  func openDocument(_ note: DidOpenTextDocumentNotification) async

  /// Sent to close a document on the Language Server.
  func closeDocument(_ note: DidCloseTextDocumentNotification) async
  func changeDocument(_ note: DidChangeTextDocumentNotification) async
  func willSaveDocument(_ note: WillSaveTextDocumentNotification) async
  func didSaveDocument(_ note: DidSaveTextDocumentNotification) async

  // MARK: - Build System Integration

  /// Sent when the `BuildSystem` has resolved build settings, such as for the intial build settings
  /// or when the settings have changed (e.g. modified build system files). This may be sent before
  /// the respective `DocumentURI` has been opened.
  func documentUpdatedBuildSettings(_ uri: DocumentURI) async

  /// Sent when the `BuildSystem` has detected that dependencies of the given file have changed
  /// (e.g. header files, swiftmodule files, other compiler input files).
  func documentDependenciesUpdated(_ uri: DocumentURI) async

  // MARK: - Text Document

  func completion(_ req: CompletionRequest) async throws -> CompletionList
  func hover(_ req: HoverRequest) async throws -> HoverResponse?
  func symbolInfo(_ request: SymbolInfoRequest) async throws -> [SymbolDetails]
  func openInterface(_ request: OpenInterfaceRequest) async throws -> InterfaceDetails?

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
  func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport

  // MARK: - Rename

  /// Entry point to perform rename.
  ///
  /// Rename is implemented as a two-step process:  This function returns all the edits it knows need to be performed.
  /// For Swift these edits are those within the current file. In addition, it can return a USR + the old name of the
  /// symbol to be renamed so that `SourceKitServer` can perform an index lookup to discover more locations to rename
  /// within the entire workspace. `SourceKitServer` will transform those into edits by calling
  /// `editsToRename(locations:in:oldName:newName:)` on the toolchain server to perform the actual rename.
  func rename(_ request: RenameRequest) async throws -> (edits: WorkspaceEdit, usr: String?, oldName: String?)

  /// Given a list of `locations``, return the list of edits that need to be performed to rename these occurrences from
  /// `oldName` to `newName`.
  func editsToRename(
    locations renameLocations: [RenameLocation],
    in snapshot: DocumentSnapshot,
    oldName: String,
    newName: String
  ) async throws -> [TextEdit]

  // MARK: - Other

  func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny?

  /// Crash the language server. Should be used for crash recovery testing only.
  func _crash() async
}
