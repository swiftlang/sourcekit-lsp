//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public extension Collection {
  /// Returns an array by skipping elements from the end while `predicate` returns `true`.
  func droppingLast(while predicate: (Element) throws -> Bool) rethrows -> [Element] {
    return try Array(self.reversed().drop(while: predicate).reversed())
  }
}
