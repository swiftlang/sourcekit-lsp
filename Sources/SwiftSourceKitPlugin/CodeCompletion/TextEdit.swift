//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

struct TextEdit: CustomStringConvertible {
  let range: Range<Position>
  let newText: String

  init(range: Range<Position>, newText: String) {
    self.range = range
    self.newText = newText
  }

  var description: String {
    "{\(range.lowerBound)-\(range.upperBound)=\(newText)}"
  }
}
