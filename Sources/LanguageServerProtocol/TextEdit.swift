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

/// Edit to a text document, replacing the contents of `range` with `text`.
public struct TextEdit: Codable, Hashable {

  /// The range of text to be replaced.
  var range: Range<Position>

  /// The new text.
  var newText: String

  public init(range: Range<Position>, newText: String) {
    self.range = range
    self.newText = newText
  }
}

extension TextEdit: ResponseType {}
