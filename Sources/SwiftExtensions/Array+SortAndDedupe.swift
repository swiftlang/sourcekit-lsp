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

extension Array where Element: Comparable {
  /// Whether the array's elements are in strictly ascending order with no duplicates.
  package var isSortedAndUnique: Bool {
    @_specialize(where Element == String)
    get {
      self.indices.dropFirst().allSatisfy { i in
        self[self.index(before: i)] < self[i]
      }
    }
  }

  /// Sorts the array in place and removes duplicate elements.
  @_specialize(where Element == String)
  package mutating func sortAndDedupe() {
    guard self.count > 1 else {
      return
    }
    let remaining = withUnsafeMutableBufferPointer { buf -> Int in
      buf.sort()
      var writeIdx = buf.startIndex
      for readIdx in buf.indices.dropFirst() {
        if buf[readIdx] == buf[writeIdx] {
          continue
        }
        buf.formIndex(after: &writeIdx)
        buf.swapAt(writeIdx, readIdx)
      }
      buf.formIndex(after: &writeIdx)
      return buf.distance(from: writeIdx, to: buf.endIndex)
    }
    self.removeLast(remaining)
  }
}
