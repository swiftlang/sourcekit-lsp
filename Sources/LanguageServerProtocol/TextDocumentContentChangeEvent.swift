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

/// A change to a text document.
///
/// If `range` and `rangeLength` are unspecified, the whole document content is replaced.
///
/// The `range.end` and `rangeLength` are potentially redundant. Based on https://github.com/Microsoft/language-server-protocol/issues/9, servers should be lenient and accept either.
public struct TextDocumentContentChangeEvent: Codable, Hashable {

      public var range: PositionRange?

      public var rangeLength: Int?

      public var text: String

      public init(
            range: Range<Position>? = nil, rangeLength: Int? = nil, text: String
      ) {
            self.range = range.map { PositionRange($0) }
            self.rangeLength = rangeLength
            self.text = text
      }
}
