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

class RejectionFilterTests: XCTestCase {
  func testMatches() throws {
    func test(pattern: RejectionFilter, candidate: RejectionFilter, match: RejectionFilter.Match) {
      XCTAssertEqual(RejectionFilter.match(pattern: pattern, candidate: candidate), match)
    }

    func test(pattern: String, candidate: String, match: RejectionFilter.Match) {
      test(pattern: RejectionFilter(string: pattern), candidate: RejectionFilter(string: candidate), match: match)
    }

    func test(pattern: [UInt8], candidate: [UInt8], match: RejectionFilter.Match) {
      test(pattern: RejectionFilter(bytes: pattern), candidate: RejectionFilter(bytes: candidate), match: match)
    }

    test(pattern: "", candidate: "", match: .maybe)
    test(pattern: "", candidate: "a", match: .maybe)
    test(pattern: "a", candidate: "a", match: .maybe)
    test(pattern: "a", candidate: "aa", match: .maybe)
    test(pattern: "aa", candidate: "a", match: .maybe)
    test(pattern: "b", candidate: "a", match: .no)
    test(pattern: "b", candidate: "ba", match: .maybe)
    test(pattern: "b", candidate: "ab", match: .maybe)
    test(pattern: "ba", candidate: "a", match: .no)
    test(pattern: "$", candidate: "$", match: .maybe)
    test(pattern: "<", candidate: "<", match: .maybe)
    test(pattern: "a", candidate: "Z", match: .no)
    test(pattern: "z", candidate: "Z", match: .maybe)
    test(pattern: "_", candidate: "a", match: .no)

    let allBytes = UInt8.min...UInt8.max
    for byte in allBytes {
      test(pattern: [], candidate: [byte], match: .maybe)
      test(pattern: [byte], candidate: [], match: .no)
      test(pattern: [byte], candidate: [byte], match: .maybe)
      test(pattern: [byte], candidate: [byte, byte], match: .maybe)
      test(pattern: [byte, byte], candidate: [byte], match: .maybe)
      test(pattern: [byte, byte], candidate: [byte, byte], match: .maybe)
    }

    for letter in UTF8Byte.lowercaseAZ {
      test(pattern: [letter], candidate: [letter], match: .maybe)
      test(pattern: [letter.uppercasedUTF8Byte], candidate: [letter], match: .maybe)
      test(pattern: [letter], candidate: [letter.uppercasedUTF8Byte], match: .maybe)
      test(pattern: [letter.uppercasedUTF8Byte], candidate: [letter.uppercasedUTF8Byte], match: .maybe)
      test(pattern: [UTF8Byte.cUnderscore], candidate: [letter.uppercasedUTF8Byte], match: .no)
      test(pattern: [letter.uppercasedUTF8Byte], candidate: [UTF8Byte.cUnderscore], match: .no)
    }

    for b1 in allBytes {
      for b2 in allBytes {
        test(pattern: [b1], candidate: [b1, b2], match: .maybe)
        test(pattern: [b1], candidate: [b2, b1], match: .maybe)
      }
    }
  }

  func testMatchesExhaustively() {
    @Sendable func matches(pattern: UnsafeBufferPointer<UTF8Byte>, candidate: UnsafeBufferPointer<UTF8Byte>) -> Bool {
      var pIdx = 0
      var cIdx = 0
      while (cIdx != candidate.count) && (pIdx != pattern.count) {
        if pattern[pIdx].lowercasedUTF8Byte == candidate[cIdx].lowercasedUTF8Byte {
          pIdx += 1
        }
        cIdx += 1
      }
      return pIdx == pattern.endIndex
    }

    @Sendable func test(pattern: UnsafeBufferPointer<UTF8Byte>, candidate: UnsafeBufferPointer<UTF8Byte>) {
      let aproximation = RejectionFilter.match(
        pattern: RejectionFilter(bytes: pattern),
        candidate: RejectionFilter(bytes: candidate)
      )
      if aproximation == .no {
        XCTAssert(!matches(pattern: pattern, candidate: candidate))
      }
    }

    DispatchQueue.concurrentPerform(iterations: Int(UInt8.max)) { pattern0 in
      let allBytes = UInt8.min...UInt8.max
      let pattern = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
      let candidate = UnsafeMutablePointer<UInt8>.allocate(capacity: 2)
      pattern[0] = UInt8(pattern0)
      for candidate0 in allBytes {
        candidate[0] = candidate0
        test(
          pattern: UnsafeBufferPointer(start: pattern, count: 1),
          candidate: UnsafeBufferPointer(start: candidate, count: 1)
        )
        for candidate1 in allBytes {
          candidate[1] = candidate1
          test(
            pattern: UnsafeBufferPointer(start: pattern, count: 1),
            candidate: UnsafeBufferPointer(start: candidate, count: 2)
          )
        }
      }
      pattern.deallocate()
      candidate.deallocate()
    }
  }
}
