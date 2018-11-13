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

/// Position within a text document, expressed as a zero-based line and column (utf-16 code unit offset).
public struct Position {

  /// Line number within a document (zero-based).
  public var line: Int

  /// UTF-16 code-unit offset from the start of a line (zero-based).
  public var utf16index: Int

  public init(line: Int, utf16index: Int) {
    self.line = line
    self.utf16index = utf16index
  }
}

extension Position: Equatable {}
extension Position: Hashable {}
extension Position: Codable {
  private enum CodingKeys: String, CodingKey {
    case line
    case utf16index = "character"
  }
}

extension Position: Comparable {
  public static func < (lhs: Position, rhs: Position) -> Bool {
    return (lhs.line, lhs.utf16index) < (rhs.line, rhs.utf16index)
  }
}

// Encode Range<Position> using the keys "start" and "end" to match the LSP protocol for "Range".
extension Range: Codable where Bound == Position {
  private enum CodingKeys: String, CodingKey {
    case lowerBound = "start"
    case upperBound = "end"
  }

  /// Create a range for a single position.
  public init(_ pos: Position) {
    self = pos ..< pos
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let lowerBound = try values.decode(Position.self, forKey: .lowerBound)
    let upperBound = try values.decode(Position.self, forKey: .upperBound)
    self = lowerBound ..< upperBound
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(lowerBound, forKey: .lowerBound)
    try container.encode(upperBound, forKey: .upperBound)
  }
}
