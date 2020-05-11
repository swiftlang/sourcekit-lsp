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

/// Request to find document ranges that should be highlighted to match the given cursor position.
///
/// This is typically used to highlight all references to the symbol under the cursor that are found
/// within a single document. Unlike the `references` request, this is scoped to one document and
/// has a DocumentHighlightKind that may include fuzzy (`.text`) matches.
///
/// Servers that provide document highlights should set the`documentHighlightProvider` server
/// capability.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///   - position: The document location at which to lookup symbol information.
///
/// - Returns: An array of document highlight ranges, if any.
public struct DocumentHighlightRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/documentHighlight"
  public typealias Response = [DocumentHighlight]?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

/// The kind of document highlight - read, write, or text (fuzzy).
public enum DocumentHighlightKind: Int, Codable, Hashable {

  /// Textual match.
  case text = 1

  /// A read of the symbol.
  case read = 2

  /// A write to the symbol.
  case write = 3
}

/// A document range to highlight.
public struct DocumentHighlight: ResponseType, Hashable {

  /// The range of the highlight.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// What kind of reference this is. Default is `.text`.
  public var kind: DocumentHighlightKind?

  public init(range: Range<Position>, kind: DocumentHighlightKind?) {
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.kind = kind
  }
}
