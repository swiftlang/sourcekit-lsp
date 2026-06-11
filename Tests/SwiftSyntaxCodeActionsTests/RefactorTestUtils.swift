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

import SwiftRefactor
import SwiftSyntax
import XCTest

func assertRefactor<R: SyntaxRefactoringProvider>(
  _ input: some SyntaxProtocol,
  context: R.Context,
  provider: R.Type,
  expected: (some SyntaxProtocol)?,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let typedInput = try XCTUnwrap(input.as(R.Input.self), file: file, line: line)
  let typedExpected = try expected.map { try XCTUnwrap($0.as(R.Output.self), file: file, line: line) }

  let refactored = try? R.refactor(syntax: typedInput, in: context)
  guard let refactored = refactored else {
    if typedExpected != nil {
      XCTFail(
        """
        Refactoring failed, expected:
        \(typedExpected?.description ?? "")
        """,
        file: file,
        line: line
      )
    }
    return
  }
  guard let typedExpected = typedExpected else {
    XCTFail(
      """
      Expected nil result, actual:
      \(refactored.description)
      """,
      file: file,
      line: line
    )
    return
  }
  assertStringsEqualWithDiff(
    refactored.description,
    typedExpected.description,
    file: file,
    line: line
  )
}

/// Asserts that the two strings are equal, providing Unix `diff`-style output if they are not.
///
/// - Parameters:
///   - actual: The actual string.
///   - expected: The expected string.
///   - message: An optional description of the failure.
///   - additionalInfo: Additional information about the failed test case that will be printed after the diff
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
func assertStringsEqualWithDiff(
  _ actual: String,
  _ expected: String,
  _ message: String = "",
  additionalInfo: @autoclosure () -> String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if actual == expected {
    return
  }
  failStringsEqualWithDiff(
    actual,
    expected,
    message,
    additionalInfo: additionalInfo(),
    file: file,
    line: line
  )
}

/// `XCTFail` with `diff`-style output.
func failStringsEqualWithDiff(
  _ actual: String,
  _ expected: String,
  _ message: String = "",
  additionalInfo: @autoclosure () -> String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let stringComparison: String

  // Use `CollectionDifference` on supported platforms to get `diff`-like line-based output. On
  // older platforms, fall back to simple string comparison.
  if #available(macOS 10.15, *) {
    let actualLines = actual.components(separatedBy: .newlines)
    let expectedLines = expected.components(separatedBy: .newlines)

    let difference = actualLines.difference(from: expectedLines)

    var result = ""

    var insertions = [Int: String]()
    var removals = [Int: String]()

    for change in difference {
      switch change {
      case .insert(let offset, let element, _):
        insertions[offset] = element
      case .remove(let offset, let element, _):
        removals[offset] = element
      }
    }

    var expectedLine = 0
    var actualLine = 0

    while expectedLine < expectedLines.count || actualLine < actualLines.count {
      if let removal = removals[expectedLine] {
        result += "–\(removal)\n"
        expectedLine += 1
      } else if let insertion = insertions[actualLine] {
        result += "+\(insertion)\n"
        actualLine += 1
      } else {
        result += " \(expectedLines[expectedLine])\n"
        expectedLine += 1
        actualLine += 1
      }
    }

    stringComparison = result
  } else {
    // Fall back to simple message on platforms that don't support CollectionDifference.
    stringComparison = """
      Expected:
      \(expected)

      Actual:
      \(actual)
      """
  }

  var fullMessage = """
    \(message.isEmpty ? "Actual output does not match the expected" : message)
    \(stringComparison)
    """
  if let additional = additionalInfo() {
    fullMessage = """
      \(fullMessage)
      \(additional)
      """
  }
  XCTFail(fullMessage, file: file, line: line)
}
