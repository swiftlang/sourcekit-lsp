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

class InfluencingIdentifiersTests: XCTestCase {

  private func score(_ candidate: String, given identifiers: [String]) -> Double {
    let tokenizedIdentifiers = MatchCollator.tokenize(
      influencingTokenizedIdentifiers: identifiers,
      filterLowSignalTokens: true
    )
    return InfluencingIdentifiers.withUnsafeInfluencingTokenizedIdentifiers(tokenizedIdentifiers) {
      influencingIdentifiers in
      influencingIdentifiers.score(text: candidate)
    }
  }

  func testEmptySets() {
    // Just test for / 0 type mistakes.
    XCTAssertEqual(score("", given: []), 0)
    XCTAssertEqual(score("document", given: []), 0)
    XCTAssertEqual(score("", given: ["document"]), 0)
  }

  private func expect(
    _ lhs: String,
    _ comparator: (Double, Double) -> Bool,
    _ rhs: String,
    whenInfluencedBy influencers: [String]
  ) {
    XCTAssert(comparator(score(lhs, given: influencers), score(rhs, given: influencers)))
  }

  func testNonMatches() {
    expect("only", >, "decoy", whenInfluencedBy: ["only"])
    expect("decoy", ==, "lure", whenInfluencedBy: ["only"])
  }

  func testIdentifierPositions() {
    expect("first", >, "second", whenInfluencedBy: ["first", "second", "third"])
    expect("second", >, "third", whenInfluencedBy: ["first", "second", "third"])
  }

  func testTokenPositions() {
    expect("first", ==, "second", whenInfluencedBy: ["firstSecondThird"])
    expect("second", ==, "third", whenInfluencedBy: ["firstSecondThird"])
  }

  func testTokenCoverage() {
    expect("first", <, "firstSecond", whenInfluencedBy: ["firstSecondThird"])
    expect("firstSecond", <, "firstSecondThird", whenInfluencedBy: ["firstSecondThird"])
    expect("second", <, "secondThird", whenInfluencedBy: ["firstSecondThird"])
    expect("firstSecond", ==, "secondThird", whenInfluencedBy: ["firstSecondThird"])
    expect("firstThird", ==, "thirdSecond", whenInfluencedBy: ["firstSecondThird"])
  }

  func testCaseInvariance() {
    expect("NSWindowController", >, "NSController", whenInfluencedBy: ["windowController"])
    expect("NSWindowController", >, "NSWindow", whenInfluencedBy: ["windowController"])
  }

  func testInertTerms() {
    // Too Short
    expect("decoy", ==, "to", whenInfluencedBy: ["to"])
    expect("decoy", ==, "URL", whenInfluencedBy: ["URL"])
    // Specifically ignored
    expect("decoy", ==, "from", whenInfluencedBy: ["from"])
    expect("decoy", ==, "with", whenInfluencedBy: ["with"])
  }
}

fileprivate extension InfluencingIdentifiers {
  func score(text: String) -> Double {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      Candidate.withAccessToCandidate(for: text, contentType: .codeCompletionSymbol) { candidate in
        score(candidate: candidate, allocator: &allocator)
      }
    }
  }
}
