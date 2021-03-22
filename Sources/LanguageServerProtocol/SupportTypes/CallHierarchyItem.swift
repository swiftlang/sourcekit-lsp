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

/// A single call hierarchy item.
public struct CallHierarchyItem: ResponseType, Hashable {
  /// Name of this item.
  public var name: String

  public var kind: SymbolKind
  public var tags: [SymbolTag]?

  /// More detail for this item, e.g. the signature of a function.
  public var detail: String?

  /// The resource identifier of this item.
  public var uri: DocumentURI

  /// The range enclosing this symbol, excluding leading/trailing whitespace
  /// but including everything else, e.g. comments and code.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The range that should be selected and revealed when this symbol is being
  /// picked, e.g. the name of a function. Must be contained by the `range`.
  @CustomCodable<PositionRange>
  public var selectionRange: Range<Position>

  /// A data entry field that is preserved between a call hierarchy prepare and
  /// incoming calls or outgoing calls requests.
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
