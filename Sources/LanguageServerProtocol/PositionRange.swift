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

/// Half-open range of Positions `[start, end)` within a text document, for use in LSP messages.
///
/// It is generally preferred to work with Range<Position> directly, but when passing values in LSP
/// messages, use PositionRange to provide the correct (de)serialization.
public struct PositionRange: Hashable {

      /// The `lowerBound` of the range (inclusive).
      public var lowerBound: Position

      /// The `upperBound` of the range (exclusive).
      public var upperBound: Position

      /// The equivalent range expressed as a `Swift.Range`.
      public var asRange: Range<Position> { return lowerBound..<upperBound }

      public init(_ range: Range<Position>) {
            self.lowerBound = range.lowerBound
            self.upperBound = range.upperBound
      }
}

extension PositionRange: Codable {
      private enum CodingKeys: String, CodingKey {
            case lowerBound = "start"
            case upperBound = "end"
      }
}

extension Range where Bound == Position {

      /// Create a range for a single position.
      public init(_ pos: Position) { self = pos..<pos }
}
