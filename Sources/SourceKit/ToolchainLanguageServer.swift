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

/// A `LanguageServer` that exists within the context of the current process.
public protocol ToolchainLanguageServer: AnyObject {

  // MARK: Lifetime

  func initializeSync(_ initialize: InitializeRequest) throws -> InitializeResult
  func clientInitialized(_ initialized: InitializedNotification)

  // MARK: - Text synchronization

  func openDocument(_ note: DidOpenTextDocument)
  func closeDocument(_ note: DidCloseTextDocument)
  func changeDocument(_ note: DidChangeTextDocument)
  func willSaveDocument(_ note: WillSaveTextDocument)
  func didSaveDocument(_ note: DidSaveTextDocument)
  func documentUpdatedBuildSettings(_ url: URL, language: Language)

  // MARK: - Text Document

  func completion(_ req: Request<CompletionRequest>)
  func hover(_ req: Request<HoverRequest>)
  func symbolInfo(_ request: Request<SymbolInfoRequest>)

  func documentSymbolHighlight(_ req: Request<DocumentHighlightRequest>)
  func foldingRange(_ req: Request<FoldingRangeRequest>)
  func documentSymbol(_ req: Request<DocumentSymbolRequest>)
  func documentColor(_ req: Request<DocumentColorRequest>)
  func colorPresentation(_ req: Request<ColorPresentationRequest>)
  func codeAction(_ req: Request<CodeActionRequest>)

  // MARK: - Other

  func executeCommand(_ req: Request<ExecuteCommandRequest>)
}
