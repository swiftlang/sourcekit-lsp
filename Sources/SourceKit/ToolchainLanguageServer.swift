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
import SKCore

/// A `LanguageServer` that exists within the context of the current process.
public protocol ToolchainLanguageServer: AnyObject {

  // MARK: Lifetime

  func initializeSync(_ initialize: InitializeRequest) throws -> InitializeResult
  func clientInitialized(_ initialized: InitializedNotification)

  // MARK: - Text synchronization

  /// Sent to open up a document on the Language Server.
  /// This may be called before or after a corresponding
  /// `documentUpdatedBuildSettings` call for the same document.
  func openDocument(_ note: DidOpenTextDocumentNotification)

  /// Sent to close a document on the Language Server.
  func closeDocument(_ note: DidCloseTextDocumentNotification)
  func changeDocument(_ note: DidChangeTextDocumentNotification)
  func willSaveDocument(_ note: WillSaveTextDocumentNotification)
  func didSaveDocument(_ note: DidSaveTextDocumentNotification)

  // MARK: - Build System Integration

  /// Sent when the `BuildSystem` has resolved build settings,
  /// such as for the intial build settings or when the settings
  /// have changed (e.g. modified build sytem files).
  func documentUpdatedBuildSettings(_ uri: DocumentURI, settings: FileBuildSettings?)
  func documentDependenciesUpdated(_ uri: DocumentURI, language: Language)

  // MARK: - Text Document

  func completion(_ req: Request<CompletionRequest>)
  func hover(_ req: Request<HoverRequest>)
  func symbolInfo(_ request: Request<SymbolInfoRequest>)

  /// Returns true if the `ToolchainLanguageServer` will take ownership of the request.
  func definition(_ request: Request<DefinitionRequest>) -> Bool

  func documentSymbolHighlight(_ req: Request<DocumentHighlightRequest>)
  func foldingRange(_ req: Request<FoldingRangeRequest>)
  func documentSymbol(_ req: Request<DocumentSymbolRequest>)
  func documentColor(_ req: Request<DocumentColorRequest>)
  func colorPresentation(_ req: Request<ColorPresentationRequest>)
  func codeAction(_ req: Request<CodeActionRequest>)

  // MARK: - Other

  func executeCommand(_ req: Request<ExecuteCommandRequest>)
}
