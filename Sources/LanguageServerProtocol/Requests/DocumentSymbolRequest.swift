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
  public typealias Response = DocumentSymbolResponse?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

public enum DocumentSymbolResponse: ResponseType, Hashable {
  case documentSymbols([DocumentSymbol])
  case symbolInformation([SymbolInformation])

  public init(from decoder: Decoder) throws {
    if let documentSymbols = try? [DocumentSymbol](from: decoder) {
      self = .documentSymbols(documentSymbols)
    } else if let symbolInformation = try? [SymbolInformation](from: decoder) {
      self = .symbolInformation(symbolInformation)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected [DocumentSymbol] or [SymbolInformation]")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .documentSymbols(let documentSymbols):
      try documentSymbols.encode(to: encoder)
    case .symbolInformation(let symbolInformation):
      try symbolInformation.encode(to: encoder)
    }
  }
}

/// Represents programming constructs like variables, classes, interfaces etc. that appear 
/// in a document. Document symbols can be hierarchical and they have two ranges: one that encloses
/// its definition and one that points to its most interesting range, e.g. the range of an identifier.
public struct DocumentSymbol: Hashable, Codable {
  
  /// The name of this symbol. Will be displayed in the user interface and therefore must not be
  /// an empty string or a string only consisting of white spaces.
  public var name: String

  /// More detail for this symbol, e.g the signature of a function.
  public var detail: String?

  /// The kind of this symbol.
  public var kind: SymbolKind

  /// Tags for this document symbol.
  public var tags: [SymbolTag]?

  /// Indicates if this symbol is deprecated.
  public var deprecated: Bool?

  /// The range enclosing this symbol not including leading/trailing whitespace but everything else
  /// like comments. This information is typically used to determine if the clients cursor is
  /// inside the symbol to reveal in the symbol in the UI.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The range that should be selected and revealed when this symbol is being picked, 
  /// e.g the name of a function.
  ///
  /// Must be contained by the `range`.
  @CustomCodable<PositionRange>
  public var selectionRange: Range<Position>

  /// Children of this symbol, e.g. properties of a class.
  public var children: [DocumentSymbol]?

  public init(
    name: String,
    detail: String? = nil,
    kind: SymbolKind,
    tags: [SymbolTag]? = nil,
    deprecated: Bool? = nil,
    range: Range<Position>,
    selectionRange: Range<Position>,
    children: [DocumentSymbol]? = nil)
  {
    self.name = name
    self.detail = detail
    self.kind = kind
    self.tags = tags
    self.deprecated = deprecated
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self._selectionRange = CustomCodable<PositionRange>(wrappedValue: selectionRange)
    self.children = children
  }
}
