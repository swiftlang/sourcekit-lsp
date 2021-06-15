//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request for inline annotations to be displayed in the editor **(LSP Extension)**.
/// 
/// This implements the proposed `textDocument/inlayHints` API from
/// https://github.com/microsoft/language-server-protocol/pull/1249 (commit: `d55733d`)
///
/// - Parameters:
///   - textDocument: The document for which to provide the inlay hints.
///
/// - Returns: InlayHints for the entire document
public struct InlayHintsRequest: TextDocumentRequest, Hashable {
  public static let method: String = "sourcekit-lsp/inlayHints"
  public typealias Response = [InlayHint]

  /// The document for which to provide the inlay hints.
  public var textDocument: TextDocumentIdentifier

  /// The range the inlay hints are requested for. If nil,
  /// hints for the entire document are requested.
  @CustomCodable<PositionRange?>
  public var range: Range<Position>?

  /// The categories of hints that are interesting to the client
  /// and should be filtered.
  public var only: [InlayHintCategory]?

  public init(
    textDocument: TextDocumentIdentifier,
    range: Range<Position>? = nil,
    only: [InlayHintCategory]? = nil
  ) {
    self.textDocument = textDocument
    self._range = CustomCodable(wrappedValue: range)
    self.only = only
  }
}
