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

/// A special text edit to provide an insert and a replace operation.
public struct InsertReplaceEdit: Codable, Hashable {
  /// The string to be inserted.
  public var newText: String

  /// The range if the insert is requested
  @CustomCodable<PositionRange>
  public var insert: Range<Position>

  /// The range if the replace is requested.
  @CustomCodable<PositionRange>
  public var replace: Range<Position>

  public init(newText: String, insert: Range<Position>, replace: Range<Position>) {
    self.newText = newText
    self.insert = insert
    self.replace = replace
  }
}
