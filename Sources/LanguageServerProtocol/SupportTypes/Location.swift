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

/// Range within a particular document.
///
/// For a location where the document is implied, use `Position` or `Range<Position>`.
public struct Location: ResponseType, Hashable, Codable, CustomDebugStringConvertible, Comparable, Sendable {
  public static func < (lhs: Location, rhs: Location) -> Bool {
    if lhs.uri != rhs.uri {
      return lhs.uri.stringValue < rhs.uri.stringValue
    }
    if lhs.range.lowerBound != rhs.range.lowerBound {
      return lhs.range.lowerBound < rhs.range.lowerBound
    }
    return lhs.range.upperBound < rhs.range.upperBound
  }

  public var uri: DocumentURI

  @CustomCodable<PositionRange>
  public var range: Range<Position>

  public init(uri: DocumentURI, range: Range<Position>) {
    self.uri = uri
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
  }

  public var debugDescription: String {
    return "\(uri):\(range.lowerBound)-\(range.upperBound)"
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      "uri": .string(uri.stringValue),
      "range": range.encodeToLSPAny()
    ])
  }
}
