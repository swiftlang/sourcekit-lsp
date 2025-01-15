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

struct Location: Equatable, CustomStringConvertible {
  let path: String
  let position: Position

  init(path: String, position: Position) {
    self.path = path
    self.position = position
  }

  var line: Int { position.line }
  var utf8Column: Int { position.utf8Column }

  var description: String {
    "\(path):\(position)"
  }
}
