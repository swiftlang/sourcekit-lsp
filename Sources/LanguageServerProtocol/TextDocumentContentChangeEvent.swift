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

/// A change to a text document.
///
/// If `range` and `rangeLength` are unspecified, the whole document content is replaced.
///
/// The `range.end` and `rangeLength` are potentially redundant. Based on https://github.com/Microsoft/language-server-protocol/issues/9, servers should be lenient and accept either.
public struct TextDocumentContentChangeEvent: Hashable {

  public var range: Range<Position>?

  public var rangeLength: Int?

  public var text: String

  public init(range: Range<Position>? = nil, rangeLength: Int? = nil, text: String) {
    self.range = range
    self.rangeLength = rangeLength
    self.text = text
  }
}

// Needs a custom implementation for range, because `Optional` is the only type that uses
// `encodeIfPresent` in the synthesized conformance, and the
// [LSP specification does not allow `null` in most places](https://github.com/microsoft/language-server-protocol/issues/355).
extension TextDocumentContentChangeEvent: Codable {
  private enum CodingKeys: String, CodingKey {
    case range
    case rangeLength
    case text
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.range = try container
      .decodeIfPresent(PositionRange.self, forKey: .range)?
      .wrappedValue
    self.rangeLength = try container.decodeIfPresent(Int.self, forKey: .rangeLength)
    self.text = try container.decode(String.self, forKey: .text)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(range.map { PositionRange(wrappedValue: $0) }, forKey: .range)
    try container.encodeIfPresent(rangeLength, forKey: .rangeLength)
    try container.encode(text, forKey: .text)
  }
}
