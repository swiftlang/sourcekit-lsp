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

import SwiftParser
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxCodeActions
import XCTest

final class FlipOperandsTests: XCTestCase {

  // MARK: - Comparison operators

  func testFlipLessThan() throws {
    try assertFlipOperands("5 < count", expected: "count > 5")
  }

  func testFlipGreaterThan() throws {
    try assertFlipOperands("count > 5", expected: "5 < count")
  }

  func testFlipLessThanOrEqual() throws {
    try assertFlipOperands("index <= limit", expected: "limit >= index")
  }

  func testFlipGreaterThanOrEqual() throws {
    try assertFlipOperands("limit >= index", expected: "index <= limit")
  }

  // MARK: - Commutative operators

  func testFlipAddition() throws {
    try assertFlipOperands("1 + value", expected: "value + 1")
  }

  func testFlipMultiplication() throws {
    try assertFlipOperands("2 * n", expected: "n * 2")
  }

  func testFlipEquality() throws {
    try assertFlipOperands("x == nil", expected: "nil == x")
  }

  func testFlipInequality() throws {
    try assertFlipOperands("x != nil", expected: "nil != x")
  }

  func testFlipLogicalAnd() throws {
    try assertFlipOperands("a && b", expected: "b && a")
  }

  func testFlipLogicalOr() throws {
    try assertFlipOperands("a || b", expected: "b || a")
  }

  func testFlipBitwiseOr() throws {
    try assertFlipOperands("flags | mask", expected: "mask | flags")
  }

  func testFlipBitwiseAnd() throws {
    try assertFlipOperands("flags & mask", expected: "mask & flags")
  }

  // MARK: - Non-flippable operators (should be unchanged)

  func testPreservesSubtraction() throws {
    try assertFlipOperands("a - b")
  }

  func testPreservesDivision() throws {
    try assertFlipOperands("a / b")
  }

  func testPreservesRemainder() throws {
    try assertFlipOperands("a % b")
  }

  // MARK: - Trivia preservation

  func testPreservesSpacing() throws {
    try assertFlipOperands("5  <  count", expected: "count  >  5")
  }

  func testPreservesLeadingTrivia() throws {
    try assertFlipOperands("/* a */ 5 < count", expected: "/* a */ count > 5")
  }

  // MARK: - In context

  func testFlipInIfCondition() throws {
    try assertFlipOperands(
      "if 5 < count { }",
      expected: "if count > 5 { }"
    )
  }

  func testFlipInWhileCondition() throws {
    try assertFlipOperands(
      "while index < limit { }",
      expected: "while limit > index { }"
    )
  }

  func testFlipWithComplexOperands() throws {
    try assertFlipOperands("foo() == bar()", expected: "bar() == foo()")
  }

  func testFlipWithMemberAccess() throws {
    try assertFlipOperands("x.count > 0", expected: "0 < x.count")
  }
}

// MARK: - Test Helper

/// Applies `FlipOperands` to all sequence expressions in the input and compares to expected.
/// When `expected` is `nil`, asserts that the input is unchanged (refactoring not applicable).
private func assertFlipOperands(
  _ input: String,
  expected: String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  var parser = Parser(input)
  let inputSyntax = SourceFileSyntax.parse(from: &parser)

  let rewriter = FlipOperandsRewriter()
  let result = rewriter.visit(inputSyntax)

  if let error = rewriter.unexpectedError {
    throw error
  }

  let resultString = result.description.trimmingCharacters(in: .newlines)
  assertStringsEqualWithDiff(resultString, expected ?? input, file: file, line: line)
}

private class FlipOperandsRewriter: SyntaxRewriter {
  var unexpectedError: (any Error)?

  override func visit(_ node: SequenceExprSyntax) -> ExprSyntax {
    let visited = super.visit(node)
    guard let seq = visited.as(SequenceExprSyntax.self) else {
      return visited
    }
    do {
      return ExprSyntax(try FlipOperands.refactor(syntax: seq, in: ()))
    } catch is RefactoringNotApplicableError {
      return ExprSyntax(seq)
    } catch {
      unexpectedError = error
      return ExprSyntax(seq)
    }
  }
}
