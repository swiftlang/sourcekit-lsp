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

extension Range where Bound == Position {

  /// Create a range for a single position.
  public init(_ pos: Position) {
    self = pos ..< pos
  }
}

/// An LSP-compatible encoding for `Range<Position>`, for use with `CustomCodable`.
public struct PositionRange: CustomCodableWrapper {
  public var wrappedValue: Range<Position>

  public init(wrappedValue: Range<Position>) {
    self.wrappedValue = wrappedValue
  }

  fileprivate enum CodingKeys: String, CodingKey {
    case lowerBound = "start"
    case upperBound = "end"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let lhs = try container.decode(Position.self, forKey: .lowerBound)
    let rhs = try container.decode(Position.self, forKey: .upperBound)
    self.wrappedValue = lhs..<rhs
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(wrappedValue.lowerBound, forKey: .lowerBound)
    try container.encode(wrappedValue.upperBound, forKey: .upperBound)
  }
}

/// An LSP-compatible encoding for `Array<Range<Position>>`, for use with `CustomCodable`.
public struct PositionRangeArray: CustomCodableWrapper {
  public var wrappedValue: [Range<Position>]

  public init(wrappedValue: [Range<Position>]) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: Decoder) throws {
    var values: [Range<Position>] = []
    var arrayContainer = try decoder.unkeyedContainer()
    values.reserveCapacity(arrayContainer.count ?? 1)

    while !arrayContainer.isAtEnd {
      let range = try arrayContainer.decode(PositionRange.self)
      values.append(range.wrappedValue)
    }
    self.wrappedValue = values
  }

  public func encode(to encoder: Encoder) throws {
    var arrayContainer = encoder.unkeyedContainer()
    for rangeValue in wrappedValue {
      try arrayContainer.encode(PositionRange(wrappedValue: rangeValue))
    }
  }
}

extension Range: LSPAnyCodable where Bound == Position {
  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .dictionary(let start)? = dictionary[PositionRange.CodingKeys.lowerBound.stringValue],
          let startPosition = Position(fromLSPDictionary: start),
          case .dictionary(let end)? = dictionary[PositionRange.CodingKeys.upperBound.stringValue],
          let endPosition = Position(fromLSPDictionary: end) else
    {
      return nil
    }
    self = startPosition..<endPosition
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      PositionRange.CodingKeys.lowerBound.stringValue: lowerBound.encodeToLSPAny(),
      PositionRange.CodingKeys.upperBound.stringValue: upperBound.encodeToLSPAny()
    ])
  }
}
