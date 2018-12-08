//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request for documentation information about the symbol at a given location.
///
/// This request looks up the symbol (if any) at a given text document location and returns the
/// documentation markup content for that location, suitable to show in an dialog when hovering over
/// that symbol in an editor.
///
/// Servers that provide document highlights should set the `hoverProvider` server capability.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///   - position: The document location at which to lookup symbol information.
///
/// - Returns: HoverResponse for the given location, which contains the `MarkupContent`.
public struct HoverRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/hover"
  public typealias Response = HoverResponse?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

/// Documentation markup contents for a symbol found by the hover request.
public struct HoverResponse: ResponseType, Hashable {

  /// The documentation markup content.
  public var contents: MarkupContent

  /// An optional range to visually distinguish during hover.
  public var range: PositionRange?

  public init(contents: MarkupContent, range: Range<Position>?) {
    self.contents = contents
    self.range = range.map { PositionRange($0) }
  }
}
