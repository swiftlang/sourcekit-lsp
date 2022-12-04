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

public struct SelectionRangeRequest: TextDocumentRequest {
  public static var method: String = "textDocument/selectionRange"
  public typealias Response = [SelectionRange]

  /// The text document.
  public var textDocument: TextDocumentIdentifier

  /// The positions inside the text document.
  public var positions: [Position]

  public init(textDocument: TextDocumentIdentifier, positions: [Position]) {
    self.textDocument = textDocument
    self.positions = positions
  }
}

public struct SelectionRange: ResponseType, Codable, Hashable {
  /// Indirect reference to a `SelectionRange`.
  final class SelectionRangeBox: Codable, Hashable {
    var selectionRange: SelectionRange

    init(selectionRange: SelectionRange) {
      self.selectionRange = selectionRange
    }

    init(from decoder: Decoder) throws {
      self.selectionRange = try SelectionRange(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
      try selectionRange.encode(to: encoder)
    }

    static func == (lhs: SelectionRange.SelectionRangeBox, rhs: SelectionRange.SelectionRangeBox) -> Bool {
      return lhs.selectionRange == rhs.selectionRange
    }

    func hash(into hasher: inout Hasher) {
      selectionRange.hash(into: &hasher)
    }
  }

  enum CodingKeys: String, CodingKey {
    case range
    case _parent = "parent"
  }

  /// The range of this selection range.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The parent selection range containing this range. Therefore
  /// `parent.range` must contain `this.range`.
  private var _parent: SelectionRangeBox?

  public var parent: SelectionRange? {
    return _parent?.selectionRange
  }

  public init(range: Range<Position>, parent: SelectionRange? = nil) {
    self.range = range
    self._parent = parent.map(SelectionRangeBox.init)
  }
}
