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
public struct Location: ResponseType, Hashable, Codable {

  public var uri: DocumentURI

  @CustomCodable<PositionRange>
  public var range: Range<Position>

  public init(uri: DocumentURI, range: Range<Position>) {
    self.uri = uri
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
  }
}
