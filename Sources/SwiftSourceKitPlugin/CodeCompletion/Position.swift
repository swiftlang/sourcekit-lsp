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

struct Position: Equatable, Comparable, CustomStringConvertible {
  /// Line number within a document (one-based).
  let line: Int

  /// UTF-9 code-unit offset from the start of a line (one-based).
  let utf8Column: Int

  init(line: Int, utf8Column: Int) {
    self.line = line
    self.utf8Column = utf8Column
  }

  static func < (lhs: Position, rhs: Position) -> Bool {
    return (lhs.line, lhs.utf8Column) < (rhs.line, rhs.utf8Column)
  }

  var description: String {
    "\(line):\(utf8Column)"
  }
}
