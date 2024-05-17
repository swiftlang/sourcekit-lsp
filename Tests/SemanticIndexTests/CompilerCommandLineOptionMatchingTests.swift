//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import SemanticIndex
import XCTest

final class CompilerCommandLineOptionMatchingTests: XCTestCase {
  func testFlags() {
    assertOption(.flag("a", [.singleDash]), "-a", .removeOption)
    assertOption(.flag("a", [.doubleDash]), "--a", .removeOption)
    assertOption(.flag("a", [.singleDash, .doubleDash]), "-a", .removeOption)
    assertOption(.flag("a", [.singleDash, .doubleDash]), "--a", .removeOption)
    assertOption(.flag("a", [.singleDash]), "-another", nil)
    assertOption(.flag("a", [.singleDash]), "--a", nil)
    assertOption(.flag("a", [.doubleDash]), "-a", nil)
  }

  func testOptions() {
    assertOption(.option("a", [.singleDash], [.noSpace]), "-a/file.txt", .removeOption)
    assertOption(.option("a", [.singleDash], [.noSpace]), "-another", .removeOption)
    assertOption(.option("a", [.singleDash], [.separatedByEqualSign]), "-a=/file.txt", .removeOption)
    assertOption(.option("a", [.singleDash], [.separatedByEqualSign]), "-a/file.txt", nil)
    assertOption(.option("a", [.singleDash], [.separatedBySpace]), "-a", .removeOptionAndNextArgument)
    assertOption(.option("a", [.singleDash], [.separatedBySpace]), "-another", nil)
    assertOption(.option("a", [.singleDash], [.separatedBySpace]), "-a=/file.txt", nil)
    assertOption(.option("a", [.singleDash], [.noSpace, .separatedBySpace]), "-a/file.txt", .removeOption)
    assertOption(.option("a", [.singleDash], [.noSpace, .separatedBySpace]), "-a=/file.txt", .removeOption)
    assertOption(.option("a", [.singleDash], [.noSpace, .separatedBySpace]), "-a", .removeOptionAndNextArgument)
    assertOption(.option("a", [.singleDash], [.separatedByEqualSign, .separatedBySpace]), "-a/file.txt", nil)
    assertOption(.option("a", [.singleDash], [.separatedByEqualSign, .separatedBySpace]), "-a=file.txt", .removeOption)
    assertOption(
      .option("a", [.singleDash], [.separatedByEqualSign, .separatedBySpace]),
      "-a",
      .removeOptionAndNextArgument
    )
  }
}

fileprivate func assertOption(
  _ option: CompilerCommandLineOption,
  _ argument: String,
  _ expected: CompilerCommandLineOption.Match?,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(option.matches(argument: argument), expected, file: file, line: line)
}
