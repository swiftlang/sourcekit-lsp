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

import BuildSystemIntegration
import XCTest

/// Assert that splitting `str` into its command line components results in `expected`.
///
/// By default assert that escaping using Unix and Windows rules results in the same split. If `windows` is specified,
/// assert that escaping with Windows rules produces `windows` and escaping using Unix rules results in `expected`.
///
/// If set `initialCommandName` gets passed to the Windows split function.
func assertEscapedCommand(
  _ str: String,
  _ expected: [String],
  windows: [String]? = nil,
  initialCommandName: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(
    splitShellEscapedCommand(str),
    expected,
    "Splitting Unix command line arguments",
    file: file,
    line: line
  )
  XCTAssertEqual(
    splitWindowsCommandLine(str, initialCommandName: initialCommandName),
    windows ?? expected,
    "Splitting Windows command line arguments",
    file: file,
    line: line
  )
}

final class SplitShellCommandTests: XCTestCase {
  func testSplitShellEscapedCommandBasic() {
    assertEscapedCommand("", [])
    assertEscapedCommand("    ", [])
    assertEscapedCommand("a", ["a"])
    assertEscapedCommand("abc", ["abc"])
    assertEscapedCommand("a😀c", ["a😀c"])
    assertEscapedCommand("😀c", ["😀c"])
    assertEscapedCommand("abc def", ["abc", "def"])
    assertEscapedCommand("abc    def", ["abc", "def"])
  }

  func testSplitShellEscapedCommandDoubleQuotes() {
    assertEscapedCommand("\"", [""])
    assertEscapedCommand(#""a"#, ["a"])
    assertEscapedCommand("\"\"", [""])
    assertEscapedCommand(#""a""#, ["a"])
    assertEscapedCommand(#""a\"""#, [#"a""#])
    assertEscapedCommand(#""a b c ""#, ["a b c "])
    assertEscapedCommand(#""a " "#, ["a "])
    assertEscapedCommand(#""a " b"#, ["a ", "b"])
    assertEscapedCommand(#""a "b"#, ["a b"])
    assertEscapedCommand(#"a"x ""b"#, ["ax b"], windows: [#"ax "b"#])

    assertEscapedCommand(#""a"bcd"ef""""g""#, ["abcdefg"], windows: [#"abcdef""g"#])
  }

  func testSplitShellEscapedCommandSingleQuotes() {
    assertEscapedCommand("'", [""], windows: ["'"])
    assertEscapedCommand("'a", ["a"], windows: ["'a"])
    assertEscapedCommand("''", [""], windows: ["''"])
    assertEscapedCommand("'a'", ["a"], windows: ["'a'"])
    assertEscapedCommand(#"'a\"'"#, [#"a\""#], windows: [#"'a"'"#])
    assertEscapedCommand(#"'a b c '"#, ["a b c "], windows: ["'a", "b", "c", "'"])
    assertEscapedCommand(#"'a ' "#, ["a "], windows: ["'a", "'"])
    assertEscapedCommand(#"'a ' b"#, ["a ", "b"], windows: ["'a", "'", "b"])
    assertEscapedCommand(#"'a 'b"#, ["a b"], windows: ["'a", "'b"])
    assertEscapedCommand(#"a'x ''b"#, ["ax b"], windows: ["a'x", "''b"])
  }

  func testSplitShellEscapedCommandBackslash() {
    assertEscapedCommand(#"a\\"#, [#"a\"#], windows: [#"a\\"#])
    assertEscapedCommand(#"a'\b "c"'"#, ["a\\b \"c\""], windows: [#"a'\b"#, #"c'"#])

    assertEscapedCommand(#"\""#, ["\""])
    assertEscapedCommand(#"\\""#, [#"\"#])
    assertEscapedCommand(#"\\\""#, [#"\""#])
    assertEscapedCommand(#"\\ "#, [#"\"#], windows: [#"\\"#])
    assertEscapedCommand(#"\\\ "#, [#"\ "#], windows: [#"\\\"#])
  }

  func testSplitShellEscapedCommandWindowsCommand() {
    assertEscapedCommand(#"C:\swift.exe"#, [#"C:swift.exe"#], windows: [#"C:\swift.exe"#], initialCommandName: true)
    assertEscapedCommand(
      #"C:\ swift.exe"#,
      [#"C: swift.exe"#],
      windows: [#"C:\"#, #"swift.exe"#],
      initialCommandName: true
    )
    assertEscapedCommand(
      #"C:\ swift.exe"#,
      [#"C: swift.exe"#],
      windows: [#"C:\"#, #"swift.exe"#],
      initialCommandName: false
    )
    assertEscapedCommand(#"C:\"swift.exe""#, [#"C:"swift.exe"#], windows: [#"C:\swift.exe"#], initialCommandName: true)
    assertEscapedCommand(#"C:\"swift.exe""#, [#"C:"swift.exe"#], windows: [#"C:"swift.exe"#], initialCommandName: false)
  }

  func testSplitShellEscapedCommandWindowsTwoDoubleQuotes() {
    assertEscapedCommand(#"" test with "" quote""#, [" test with  quote"], windows: [#" test with " quote"#])
    assertEscapedCommand(#"" test with "" quote""#, [" test with  quote"], windows: [#" test with " quote"#])
  }
}
