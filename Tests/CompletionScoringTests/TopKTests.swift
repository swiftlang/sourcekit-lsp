//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring
import XCTest

class TopKTests: XCTestCase {
  func testSelectTopK() throws {
    func select(k: Int, from: [Int]) -> [Int] {
      from.fastTopK(k, lessThan: <)
    }

    func test(_ all: [Int], _ expected: [Int]) {
      XCTAssertEqual(all.fastTopK(expected.count, lessThan: <).sorted(by: <), expected.sorted(by: <))
    }

    test([], [])
    test([1], [1])
    test([1, 2], [1])
    test([2, 1], [1])
    test([1, 2, 3], [1])
    test([1, 2, 3], [1, 2])
    test([1, 2, 3], [1, 2, 3])
    test([3, 2, 1], [1])
    test([3, 2, 1], [1, 2])
    test([3, 2, 1], [1, 2, 3])
  }

  func testSelectTopKExhaustively() throws {
    func allCombinations(count: Int, body: ([Int]) -> ()) {
      var array = [Int](repeating: 0, count: count)
      func enumerate(slot: Int) {
        if slot == array.count {
          body(array)
        } else {
          for x in 0..<count {
            array[slot] = x
            enumerate(slot: slot + 1)
          }
        }
      }
      enumerate(slot: 0)
    }

    for count in 0..<7 {
      allCombinations(count: count) { permutation in
        for k in 0..<count {
          let fastResult = permutation.fastTopK(k, lessThan: <).sorted(by: <)
          let slowResult = permutation.slowTopK(k, lessThan: <).sorted(by: <)
          XCTAssertEqual(fastResult, slowResult)
        }
      }
    }
  }
}

fileprivate extension Array {
  func fastTopK(_ k: Int, lessThan: (Element, Element) -> Bool) -> [Element] {
    var copy = UnsafeMutableBufferPointer.allocate(copyOf: self); defer { copy.deinitializeAllAndDeallocate() }
    copy.selectTopKAndTruncate(k, lessThan: lessThan)
    return Array(copy)
  }

  func slowTopK(_ k: Int, lessThan: (Element, Element) -> Bool) -> Self {
    Array(sorted(by: lessThan).prefix(k))
  }
}
