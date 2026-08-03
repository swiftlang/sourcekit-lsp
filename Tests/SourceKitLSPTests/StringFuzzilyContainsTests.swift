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

@_spi(Testing) import SourceKitLSP
import XCTest

final class StringFuzzilyContainsTests: XCTestCase {
  func testEmptySubsequenceAlwaysMatches() {
    XCTAssertTrue("anything".fuzzilyContains(subsequence: ""))
    XCTAssertTrue("".fuzzilyContains(subsequence: ""))
  }

  func testSubsequenceMatching() {
    XCTAssertTrue("longMethodName()".fuzzilyContains(subsequence: "longMethod"))
    XCTAssertTrue("longMethodName()".fuzzilyContains(subsequence: "lmn"))
    XCTAssertTrue("bar()".fuzzilyContains(subsequence: "bar"))
  }

  func testCaseInsensitive() {
    XCTAssertTrue("MyMethod".fuzzilyContains(subsequence: "mym"))
    XCTAssertTrue("mymethod".fuzzilyContains(subsequence: "MYM"))
  }

  func testNonMatching() {
    XCTAssertFalse("bar".fuzzilyContains(subsequence: "baz"))
    XCTAssertFalse("bar".fuzzilyContains(subsequence: "barbar"))
    XCTAssertFalse("".fuzzilyContains(subsequence: "a"))
  }
}
