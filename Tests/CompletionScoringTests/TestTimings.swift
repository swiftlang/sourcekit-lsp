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
import CompletionScoringTestSupport
import XCTest

class TestTimings: XCTestCase {
  func test<R: Equatable>(_ values: [Double], _ accessor: (Timings) -> R, _ expected: R) {
    let actual = accessor(Timings(values))
    XCTAssertEqual(actual, expected)
  }

  func test<R: Equatable>(_ values: [Double], _ accessor: (Timings) -> R, _ expected: Range<R>) {
    let actual = accessor(Timings(values))
    XCTAssert(expected.contains(actual))
  }

  func testMin() {
    test([], \.stats?.min, nil)
    test([4], \.stats?.min, 4)
    test([4, 2], \.stats?.min, 2)
    test([4, 2, 9], \.stats?.min, 2)
  }

  func testAverage() {
    test([], \.stats?.min, nil)
    test([4], \.stats?.min, 4)
    test([4, 2], \.stats?.min, 2)
    test([4, 2, 9], \.stats?.min, 2)
  }

  func testMax() {
    test([], \.stats?.max, nil)
    test([4], \.stats?.max, 4)
    test([4, 2], \.stats?.max, 4)
    test([4, 2, 9], \.stats?.max, 9)
  }

  func testAverageDeviation() {
    test([], \.meanAverageDeviation, 0)
    test([2], \.meanAverageDeviation, 0)
    test([2, 2], \.meanAverageDeviation, 0)
    test([2, 4], \.meanAverageDeviation, 1)
  }

  func testStandardDeviation() {
    test([], \.standardDeviation, 0)
    test([2], \.standardDeviation, 0)
    test([2, 2], \.standardDeviation, 0)
    test([2, 4, 6, 2, 6], \.standardDeviation, 2)
    test([1, 2, 3, 4, 5], \.standardDeviation, 1.5811..<1.5812)
  }

  func testStandardError() {
    test([], \.standardError, 0)
    test([2], \.standardError, 0)
    test([2, 2], \.standardError, 0)
    test([1, 2, 3, 4, 5], \.standardError, 0.70710..<0.70711)
    test([1, 2, 4, 8, 16], \.standardError, 2.72763..<2.72764)
  }
}
