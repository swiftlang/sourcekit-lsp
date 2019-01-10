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

extension RandomAccessCollection where Element: Equatable & Hashable {

  /// Searches back through both patterns until we find an element that
  /// doesn’t match or until we’ve reached the beginning of the pattern.
  @inlinable
  public func backwards<Pattern>(on pattern: Pattern, i: Index) -> Index? where Pattern: RandomAccessCollection, Pattern.Element == Element {
    var q = pattern.index(before: pattern.endIndex)
    var j = i
    while q > pattern.startIndex {
      j = index(before: j)
      q = pattern.index(before: q)
      if self[j] != pattern[q] {
        return nil
      }
    }
    return j
  }

  /// Returns the first index where the specified subsequence appears or nil.
  @inlinable
  public func firstIndex<Pattern>(of pattern: Pattern) -> Index? where Pattern: RandomAccessCollection, Pattern.Element == Element {

    if pattern.isEmpty {
      return startIndex
    }
    if count < pattern.count {
      return nil
    }

    let patternLength = pattern.count

    // Table determines how far we skip ahead when an element from the pattern is found.
    var table = [Element: Int]()
    for (i, e) in pattern.enumerated() {
      table[e] = patternLength - i - 1
    }

    let p = pattern.index(before: pattern.endIndex)
    let lastElement = pattern[p]

    // Scan right to left, so skip ahead in the element by the length of the pattern.
    var i = index(startIndex, offsetBy: patternLength - 1)

    // Keep going until the end of the element is reached.
    while i < endIndex {
      let element = self[i]
      if element == lastElement {
        // Search backwards for possible match.
        if let k = backwards(on: pattern, i: i) {
          return k
        }
        // Jump at least one element
        let jumpOffset = Swift.max(table[element] ?? patternLength, 1)
        i = index(i, offsetBy: jumpOffset, limitedBy: endIndex) ?? endIndex
      } else {
        // The elements are not equal, so skip.
        i = index(i, offsetBy: table[element] ?? patternLength, limitedBy: endIndex) ?? endIndex
      }
    }
    return nil
  }
}
