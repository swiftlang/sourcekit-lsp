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
import Foundation
import XCTest

class SwiftExtensionsTests: XCTestCase {
  func testCompareBytes() {
    func compare(_ lhsText: String, _ rhsText: String) -> ComparisonOrder {
      Candidate.withAccessToCandidate(for: lhsText, contentType: .codeCompletionSymbol) { lhsCandidate in
        Candidate.withAccessToCandidate(for: rhsText, contentType: .codeCompletionSymbol) { rhsCandidate in
          compareBytes(lhsCandidate.bytes, rhsCandidate.bytes)
        }
      }
    }

    XCTAssertEqual(compare("", ""), .same)
    XCTAssertEqual(compare("", "a"), .ascending)
    XCTAssertEqual(compare("a", ""), .descending)
    XCTAssertEqual(compare("a", "b"), .ascending)
    XCTAssertEqual(compare("b", "a"), .descending)
    XCTAssertEqual(compare("a", "a"), .same)
    XCTAssertEqual(compare("ab", "ba"), .ascending)
    XCTAssertEqual(compare("a", "ba"), .ascending)
    XCTAssertEqual(compare("a", "ab"), .ascending)
    XCTAssertEqual(compare("ab", "a"), .descending)
    XCTAssertEqual(compare("ba", "a"), .descending)
  }

  func testConcurrentCompactMap() {
    var randomness = RepeatableRandomNumberGenerator()
    for _ in 0..<1000 {
      let strings = randomness.randomLowercaseASCIIStrings(countRange: 0...100, lengthRange: 0...15)
      @Sendable func mappingFunction(_ string: String) -> Int? {
        return string.first == "b" ? string.count : nil
      }
      let concurrentResults = strings.concurrentCompactMap(mappingFunction)
      let serialResults = strings.compactMap(mappingFunction)
      XCTAssertEqual(concurrentResults, serialResults)
    }
  }

  func testMinMaxBy() {
    func test(min: String?, max: String?, in array: [String]) {
      XCTAssertEqual(array.min(by: \.count), min)
      XCTAssertEqual(array.max(by: \.count), max)
    }

    test(min: "a", max: "a", in: ["a"])
    test(min: "a", max: "a", in: ["a", "b"])
    test(min: "a", max: "bb", in: ["a", "bb"])
    test(min: "a", max: "bb", in: ["bb", "a"])
    test(min: "a", max: "ccc", in: ["a", "bb", "ccc", "dd", "e"])
    test(min: nil, max: nil, in: [])
  }

  func testMinMaxOf() {
    func test(min: Int?, max: Int?, in array: [String]) {
      XCTAssertEqual(array.min(of: \.count), min)
      XCTAssertEqual(array.max(of: \.count), max)
    }

    test(min: 1, max: 1, in: ["a"])
    test(min: 1, max: 1, in: ["a", "b"])
    test(min: 1, max: 2, in: ["a", "bb"])
    test(min: 1, max: 2, in: ["bb", "a"])
    test(min: 1, max: 3, in: ["a", "bb", "ccc", "dd", "e"])
    test(min: nil, max: nil, in: [])
  }

  func testConcurrentMap() {
    func test(_ input: [String], transform: @Sendable (String) -> String) {
      let serialOutput = input.map(transform)
      let concurrentOutput = input.concurrentMap(transform)
      let unsafeConcurrentSliceOutput: [String] = input.unsafeSlicedConcurrentMap { (slice, baseAddress) in
        for (outputIndex, input) in slice.enumerated() {
          baseAddress.advanced(by: outputIndex).initialize(to: transform(input))
        }
      }
      XCTAssertEqual(serialOutput, concurrentOutput)
      XCTAssertEqual(serialOutput, unsafeConcurrentSliceOutput)
    }

    let strings = (0..<1000).map { index in
      String(repeating: "a", count: index)
    }
    for stringCount in 0..<strings.count {
      test(Array(strings[0..<stringCount])) { string in
        string.uppercased()
      }
    }
  }

  func testRangeOfBytes() {
    func search(for needle: String, in body: String, expecting expectedMatch: Range<Int>?, line: UInt = #line) {
      needle.withUncachedUTF8Bytes { needle in
        body.withUncachedUTF8Bytes { body in
          let actualMatch = body.rangeOf(bytes: needle)
          XCTAssertEqual(actualMatch, expectedMatch, line: line)
        }
      }
    }
    search(for: "", in: "", expecting: nil)
    search(for: "A", in: "", expecting: nil)
    search(for: "A", in: "B", expecting: nil)
    search(for: "A", in: "BB", expecting: nil)
    search(for: "AA", in: "", expecting: nil)
    search(for: "AA", in: "B", expecting: nil)

    search(for: "A", in: "A", expecting: 0 ..+ 1)
    search(for: "A", in: "AB", expecting: 0 ..+ 1)
    search(for: "A", in: "BA", expecting: 1 ..+ 1)
    search(for: "AA", in: "AAB", expecting: 0 ..+ 2)
    search(for: "AA", in: "BAA", expecting: 1 ..+ 2)
  }

  func testSingleElementBuffer() {
    func test<T: Equatable>(_ value: T) {
      var callCount = 0
      UnsafeBufferPointer.withSingleElementBuffer(of: value) { buffer in
        callCount += 1
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.first, value)
      }
      XCTAssertEqual(callCount, 1)
    }
    test(0)
    test(1)
    test(0.0)
    test(1.0)
    test(0..<1)
    test(1..<2)
    test(UInt8(0))
    test(UInt8(1))
    test("")
    test("S")
  }
}

private struct CompletionItem {
  var score: Double
  var text: String
}

extension CompletionItem: Comparable {
  static func < (lhs: Self, rhs: Self) -> Bool {
    return (lhs.score <? rhs.score)
      ?? (lhs.text < rhs.text)
  }
}
