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

extension RandomAccessCollection where Element: Equatable {

  /// Returns the first index where the specified subsequence appears or nil.
  @inlinable
  public func firstIndex<Pattern>(of pattern: Pattern) -> Index? where Pattern: RandomAccessCollection, Pattern.Element == Element {

    if pattern.isEmpty {
      return startIndex
    }
    if count < pattern.count {
      return nil
    }

    // FIXME: use a better algorithm (e.g. Boyer-Moore-Horspool).
    var i = startIndex
    for _ in 0 ..< (count - pattern.count + 1) {
      if self[i...].starts(with: pattern) {
        return i
      }
      i = self.index(after: i)
    }
    return nil
  }
}
