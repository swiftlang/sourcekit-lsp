//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A single type hierarchy item.
public struct TypeHierarchyItem: ResponseType, Hashable {
  /// Name of this item.
  public var name: String
  /// The kind of this item.
  public var kind: SymbolKind
  /// Tags for this item
  public var tags: [SymbolTag]?
  /// More detail for this item.
  public var detail: String?

  /// The resource identifier of this item.
  public var uri: DocumentURI

  /// The range enclosing this symbol not including leading/trailing whitespace
  /// but everything else, e.g. comments and code.
  @CustomCodable<PositionRange>
  public var range: Range<Position>
  /// The range that should be selected and revealed when this symbol is being picked.
  @CustomCodable<PositionRange>
  public var selectionRange: Range<Position>

  /// A data entry field that is preserved between a type hierarchy prepare and
  /// subtype/supertype requests.
  public var data: LSPAny?

  public init(
    name: String,
    kind: SymbolKind,
    tags: [SymbolTag]?,
    detail: String? = nil,
    uri: DocumentURI,
    range: Range<Position>,
    selectionRange: Range<Position>,
    data: LSPAny? = nil
  ) {
    self.name = name
    self.kind = kind
    self.tags = tags
    self.detail = detail
    self.uri = uri
    self.range = range
    self.selectionRange = selectionRange
    self.data = data
  }
}
