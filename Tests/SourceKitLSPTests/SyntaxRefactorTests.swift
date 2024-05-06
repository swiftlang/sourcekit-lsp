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

@_spi(Testing) import SourceKitLSP
import SwiftParser
import SwiftRefactor
import SwiftSyntax
import XCTest

final class SyntaxRefactorTests: XCTestCase {
  func testAddDocumentationRefactor() throws {
    try assertRefactor(
      """
        func refactor(syntax: DeclSyntax, in context: Void) -> DeclSyntax? { }
      """,
      context: (),
      provider: AddDocumentation.self,
      expected: [
        SourceEdit(
          range: AbsolutePosition(utf8Offset: 0)..<AbsolutePosition(utf8Offset: 0),
          replacement: """

              /// A description
              /// - Parameters:
              ///   - syntax:
              ///   - context:
              ///
              /// - Returns:
            """
        )
      ]
    )
  }
}

func assertRefactor<R: EditRefactoringProvider>(
  malformedInput input: String,
  context: R.Context,
  provider: R.Type,
  expected: [SourceEdit],
  file: StaticString = #filePath,
  line: UInt = #line
) throws where R.Input == Syntax {
  var parser = Parser(input)
  let syntax = ExprSyntax.parse(from: &parser)
  try assertRefactor(
    Syntax(syntax),
    context: context,
    provider: provider,
    expected: expected,
    file: file,
    line: line
  )
}

// Borrowed from the swift-syntax library's SwiftRefactor tests.

func assertRefactor<R: EditRefactoringProvider>(
  _ input: R.Input,
  context: R.Context,
  provider: R.Type,
  expected: [SourceEdit],
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let edits = R.textRefactor(syntax: input, in: context)
  guard !edits.isEmpty else {
    if !expected.isEmpty {
      XCTFail(
        """
        Refactoring produced empty result, expected:
        \(expected)
        """,
        file: file,
        line: line
      )
    }
    return
  }

  if edits.count != expected.count {
    XCTFail(
      """
      Refactoring produced incorrect number of edits, expected \(expected.count) not \(edits.count).

      Actual:
      \(edits.map({ $0.debugDescription }).joined(separator: "\n"))

      Expected:
      \(expected.map({ $0.debugDescription }).joined(separator: "\n"))

      """,
      file: file,
      line: line
    )
    return
  }

  for (actualEdit, expectedEdit) in zip(edits, expected) {
    XCTAssertEqual(
      actualEdit,
      expectedEdit,
      "Incorrect edit, expected \(expectedEdit.debugDescription) but actual was \(actualEdit.debugDescription)",
      file: file,
      line: line
    )
    assertStringsEqualWithDiff(
      actualEdit.replacement,
      expectedEdit.replacement,
      file: file,
      line: line
    )
  }
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
public func assertStringsEqualWithDiff(
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

/// Asserts that the two data are equal, providing Unix `diff`-style output if they are not.
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
public func assertDataEqualWithDiff(
  _ actual: Data,
  _ expected: Data,
  _ message: String = "",
  additionalInfo: @autoclosure () -> String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if actual == expected {
    return
  }

  // NOTE: Converting to `Stirng` here looses invalid UTF8 sequence difference,
  // but at least we can see something is different.
  failStringsEqualWithDiff(
    String(decoding: actual, as: UTF8.self),
    String(decoding: expected, as: UTF8.self),
    message,
    additionalInfo: additionalInfo(),
    file: file,
    line: line
  )
}

/// `XCTFail` with `diff`-style output.
public func failStringsEqualWithDiff(
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