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

/// Request for symbols to display in the document outline.
///
/// This is used to provide list of all symbols in the document and display inside which 
/// type or function the cursor is currently in.
///
/// Servers that provide document highlights should set the `documentSymbolProvider` server
/// capability.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///
/// - Returns: An array of document symbols, if any.
public struct DocumentSymbolRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/documentSymbol"
  public typealias Response = [DocumentSymbol]?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

/// Represents programming constructs like variables, classes, interfaces etc. that appear 
/// in a document. Document symbols can be hierarchical and they have two ranges: one that encloses
/// its definition and one that points to its most interesting range, e.g. the range of an identifier.
public struct DocumentSymbol: Hashable, Codable, ResponseType {
  
  /// The name of this symbol. Will be displayed in the user interface and therefore must not be
  /// an empty string or a string only consisting of white spaces.
  var name: String

  /// More detail for this symbol, e.g the signature of a function.
  var detail: String?

  /// The kind of this symbol.
  var kind: SymbolKind

  /// Indicates if this symbol is deprecated.
  var deprecated: Bool?

  /// The range enclosing this symbol not including leading/trailing whitespace but everything else
  /// like comments. This information is typically used to determine if the clients cursor is
  /// inside the symbol to reveal in the symbol in the UI.
  var range: PositionRange

  /// The range that should be selected and revealed when this symbol is being picked, 
  /// e.g the name of a function.
  ///
  /// Must be contained by the `range`.
  var selectionRange: PositionRange

  /// Children of this symbol, e.g. properties of a class.
  var children: [DocumentSymbol]?

  public init(
    name: String,
    detail: String?, 
    kind: SymbolKind,
    deprecated: Bool?,
    range: PositionRange,
    selectionRange: PositionRange,
    children: [DocumentSymbol]?)
  {
    self.name = name
    self.detail = detail
    self.kind = kind
    self.deprecated = deprecated
    self.range = range
    self.selectionRange = selectionRange
    self.children = children
  }
}
