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

final class RemoveRedundantParenthesesTests: XCTestCase {

  func testRemovesRedundantParentheses() throws {
    try assertParenRemoval("((1))", expected: "1")
    try assertParenRemoval("((x))", expected: "x")
    try assertParenRemoval("((x + y))", expected: "(x + y)")
    try assertParenRemoval("(x)", expected: "x")
    try assertParenRemoval("(1)", expected: "1")
    try assertParenRemoval("(\"s\")", expected: "\"s\"")
    try assertParenRemoval("(true)", expected: "true")
    try assertParenRemoval("(x.y)", expected: "x.y")
    try assertParenRemoval("(f(x))", expected: "f(x)")
    try assertParenRemoval("(x[0])", expected: "x[0]")
    try assertParenRemoval("([1, 2])", expected: "[1, 2]")
    try assertParenRemoval("([:])", expected: "[:]")
    try assertParenRemoval("({ x in x })", expected: "{ x in x }")
    try assertParenRemoval(
      "(#colorLiteral(red: 1, green: 1, blue: 1, alpha: 1))",
      expected: "#colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)"
    )
    try assertParenRemoval("(try! f())", expected: "try! f()")
    try assertParenRemoval("(try? f())", expected: "try? f()")
    try assertParenRemoval("(await f())", expected: "await f()")
    try assertParenRemoval("(x?.y)", expected: "x?.y")
    try assertParenRemoval("(x!)", expected: "x!")
    try assertParenRemoval("(nil)", expected: "nil")
  }

  func testPreservesNecessaryParentheses() throws {
    try assertParenRemoval("(1 + 2)")
    try assertParenRemoval("(x as T)")
    try assertParenRemoval("(x ? y : z)")
    try assertParenRemoval("({ true }())")
    // try without ! or ? requires parentheses for precedence
    try assertParenRemoval("(try f())")
    // await with complex expression requires parentheses
    try assertParenRemoval("(await 1 + 2)")

    // Complex called expressions in function calls need parentheses
    try assertParenRemoval("(a + b)()")
    try assertParenRemoval("(a as! () -> Void)()")
    // Outer parentheses should still be removable if the inner one is preserved
    try assertParenRemoval("((a + b)())", expected: "(a + b)()")

    // IIFE must keep parentheses around the closure
    try assertParenRemoval("({ 1 })()")
  }

  func testTupleHandling() throws {
    // Nested tuple: outer parens removed, inner tuple preserved
    try assertParenRemoval("((x, y))", expected: "(x, y)")
    // Single element with trailing comma: treated as parentheses, removed
    try assertParenRemoval("(x,)", expected: "x")
    // Two-element tuple: preserved
    try assertParenRemoval("(x, y)", expected: "(x, y)")
  }

  func testPreservesTrivia() throws {
    try assertParenRemoval(
      "/* a */ (( /* b */ x /* c */ )) /* d */",
      expected: "/* a */ /* b */ x /* c */  /* d */"
    )
  }

  func testInitializerClauseRemovesParentheses() throws {
    // `let x = (a + b)` removes parens because InitializerClauseSyntax context
    try assertParenRemoval("let x = (a + b)", expected: "let x = a + b")
    try assertParenRemoval("let x = ((1))", expected: "let x = 1")

    // `if let` and `guard let` initializers also remove parentheses
    try assertParenRemoval("if let x = (a + b) {}", expected: "if let x = a + b {}")
    try assertParenRemoval("if var x = (a + b) {}", expected: "if var x = a + b {}")
    try assertParenRemoval("guard let x = (a + b) else {}", expected: "guard let x = a + b else {}")

    // `try f()` is not a "simple expression", but in an initializer clause the parentheses are still redundant.
    try assertParenRemoval("let x = (try f())", expected: "let x = try f()")
  }

  func testPreservesParenthesesInConditions() throws {
    // Closures in conditions need parentheses
    try assertParenRemoval("if ({ true }) {}")
    try assertParenRemoval("if (call { true }) {}")
    try assertParenRemoval("while ({ true }) {}")
    try assertParenRemoval("guard (call { true }) else {}")
    // Nested in sequence expressions
    try assertParenRemoval("if ({ true }) == ({ true }) {}")
    // Macro expansions with trailing closures
    try assertParenRemoval("if (#macro { true }) == false {}")
    // Subscripts with trailing closures
    try assertParenRemoval("if (array[0] { true }) == false {}")

    // Complex trailing closures in conditions
    try assertParenRemoval("if (call { true }) == false {}")
    try assertParenRemoval("if let x: () -> Bool = ({ true }) {}")

    // Immediately-invoked closures in conditions must keep parentheses.
    try assertParenRemoval("if ({ true }()) {}")

    // Trivia around parentheses should be preserved when parentheses are required.
    try assertParenRemoval(
      "if /*a*/ ( /*b*/ { true }() /*c*/ ) /*d*/ {}"
    )

    // Repeat-while conditions with nested or trailing closures
    try assertParenRemoval("repeat {} while call(({ true }))")
    try assertParenRemoval("repeat {} while (call { true })")
  }

  func testPreservesParenthesesForMetatypes() throws {
    // e.g., `(any Equatable).self` must not become `any Equatable.self`
    try assertParenRemoval("(any Equatable).self")
    try assertParenRemoval("(some P).self")
    try assertParenRemoval("(A & B).self")
    try assertParenRemoval("(any Equatable).Type")
    try assertParenRemoval("(some P).Type")
    try assertParenRemoval("(A & B).Type")
    try assertParenRemoval("(any Equatable).Protocol")
    try assertParenRemoval("(A & B).Protocol")
    try assertParenRemoval("(@escaping () -> Int).self")
    try assertParenRemoval("(T...).self")

    // Simple types allow removing parentheses
    try assertParenRemoval("(MyStruct).self", expected: "MyStruct.self")
    try assertParenRemoval("(Int).Type", expected: "Int.Type")
    try assertParenRemoval("(Double).Protocol", expected: "Double.Protocol")
  }

  func testPreservesParenthesesForPostfixExpressions() throws {
    // `try?` binds looser than member access.
    // `(try? f()).description` operates on `Optional<T>`, while `try? f().description` operates on `T`.
    try assertParenRemoval("(try? f()).description")
    try assertParenRemoval("(try! f()).description")

    // `try?` also binds looser than optional chaining.
    // `(try? f())?.bar` is different from `try? f()?.bar`.
    try assertParenRemoval("(try? f())?.bar")
    try assertParenRemoval("(try! f())?.bar")

    // `await` also binds looser than member access.
    try assertParenRemoval("(await f()).description")

    // `consume` and `copy` also bind looser than member access.
    try assertParenRemoval("(consume x).property")
    try assertParenRemoval("(copy x).property")

    // Infix operators bind tighter than effects
    // `(try? f()) + 1` is `Optional<Int> + Int` while `try? f() + 1` is `Int + Int`.
    try assertParenRemoval("(try? f()) + 1")
    try assertParenRemoval("(try! f()) + 1")
    try assertParenRemoval("(await f()) + 1")

    // Type casting binds tighter than effects
    // `(try? f()) as Int` is different from `try? f() as Int`.
    try assertParenRemoval("(try? f()) as Int")
    try assertParenRemoval("(try! f()) as Int")
    try assertParenRemoval("(await f()) as Int")
    // `is` check
    try assertParenRemoval("(try? f()) is Int")

    // Ternary operator binds tighter than effects
    // `(try? f()) ? x : y` is different from `try? f() ? x : y`.
    try assertParenRemoval("(try? f()) ? x : y")
    try assertParenRemoval("(await f()) ? x : y")

    // Force unwrap binds tighter than effects
    // `(try? f())!` is different from `try? f()!`.
    try assertParenRemoval("(try? f())!")
    try assertParenRemoval("(await f())!")
  }

  func testPreservesParenthesesForEffectsInConditionsAndStatements() throws {
    // Conditions should not drop parentheses that preserve effect binding.
    try assertParenRemoval(
      "if (try? f()).description == \"x\" {}"
    )
    try assertParenRemoval(
      "if (await f()).description == \"x\" {}"
    )

    // Return/throw should not drop parentheses that preserve effect binding.
    try assertParenRemoval("return (try? f()).description")
    try assertParenRemoval("throw (try? f()).description")

    // Switch subject should not drop parentheses that preserve effect binding.
    try assertParenRemoval(
      "switch (try? f()).description { default: break }"
    )
  }

  func testRedundantParenthesesInControlFlow() throws {
    // Control flow conditions
    try assertParenRemoval("if (x == y) {}", expected: "if x == y {}")
    try assertParenRemoval("while (x > 10) {}", expected: "while x > 10 {}")
    try assertParenRemoval("guard (x && y) else { return }", expected: "guard x && y else { return }")
    try assertParenRemoval("repeat {} while (x || y)", expected: "repeat {} while x || y")

    // Switch statement
    try assertParenRemoval("switch (x) { default: break }", expected: "switch x { default: break }")

    // Return and Throw
    try assertParenRemoval("return (x + y)", expected: "return x + y")
    try assertParenRemoval("throw (e)", expected: "throw e")

    // Compound expressions in conditions
    try assertParenRemoval("if (x + y > z) {}", expected: "if x + y > z {}")

    // Multiple conditions
    try assertParenRemoval("if (x), (y) {}", expected: "if x, y {}")
  }

  func testPreservesParenthesesInSwitchSubject() throws {
    // A closure literal as the switch subject requires parentheses.
    // `switch { true } {}` is invalid syntax.
    try assertParenRemoval(
      "switch ({ true }) { default: break }"
    )

    // Trailing closures in switch subjects should keep parentheses to avoid ambiguity warnings.
    try assertParenRemoval(
      "switch (call { true }) { default: break }"
    )

    // Macro expansions with trailing closures in switch subjects should keep parentheses.
    try assertParenRemoval(
      "switch (#macro { true }) { default: break }"
    )

    // Subscripts with trailing closures in switch subjects should keep parentheses.
    try assertParenRemoval(
      "switch (array[0] { true }) { default: break }"
    )

    // Trailing closures inside switch subject expressions should keep parentheses.
    try assertParenRemoval(
      "switch (call { true }) == false { default: break }"
    )

    // Immediately-invoked closures in switch subjects must keep parentheses.
    try assertParenRemoval(
      "switch ({ true }()) { default: break }"
    )
  }

  func testPreservesParenthesesInForInSequence() throws {
    // Trailing closures in for-in sequences should keep parentheses to avoid ambiguity warnings.
    try assertParenRemoval(
      "for _ in (call { true }) {}"
    )

    // Macro expansions with trailing closures in for-in sequences should keep parentheses.
    try assertParenRemoval(
      "for _ in (#macro { true }) {}"
    )

    // Subscripts with trailing closures in for-in sequences should keep parentheses.
    try assertParenRemoval(
      "for _ in (array[0] { true }) {}"
    )

    // Immediately-invoked closures in for-in sequences must keep parentheses.
    try assertParenRemoval(
      "for _ in ({ true }()) {}"
    )

    // Trivia around parentheses should be preserved when parentheses are required.
    try assertParenRemoval(
      "for _ in /*a*/ ( /*b*/ call { true } /*c*/ ) /*d*/ {}"
    )
  }

  func testPreservesParenthesesInWhereClauses() throws {
    // Trailing closures in catch-where clauses should keep parentheses.
    try assertParenRemoval(
      "do {} catch where (call { true }) { }"
    )

    // Trailing closures in for-in where clauses should keep parentheses.
    try assertParenRemoval(
      "for _ in [1] where (call { true }) {}"
    )

    // Trivia around parentheses should be preserved when parentheses are required.
    try assertParenRemoval(
      "for _ in [1] where /*a*/ ( /*b*/ call { true } /*c*/ ) /*d*/ {}"
    )
  }

  func testSequenceExpressions() throws {
    // Sequence expressions (before SwiftOperators folding) bind tighter than effects.
    // In `(try? f()) + 1`, the parentheses must be preserved because the sequence
    // expression structure makes `try? f()` the left operand of `+`.
    try assertParenRemoval("(try? f()) - 1")
    try assertParenRemoval("(try? f()) * 1")

    // Complex sequence expressions
    try assertParenRemoval("(try? f()) + g() + h()")
    try assertParenRemoval("(await f()) + g()")
  }

  func testParenthesesInRepeatWhileBody() throws {
    try assertParenRemoval(
      "repeat { (x) } while true",
      expected: "repeat { x } while true"
    )
  }

}

// MARK: - Test Helper

/// Applies `RemoveRedundantParentheses` to all tuple expressions in the input and compares to expected.
/// When `expected` is `nil`, asserts that the input is unchanged.
private func assertParenRemoval(
  _ input: String,
  expected: String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  var parser = Parser(input)
  let inputSyntax = SourceFileSyntax.parse(from: &parser)

  let rewriter = ParenRemovalRewriter()
  let result = rewriter.visit(inputSyntax)

  if let error = rewriter.unexpectedError {
    throw error
  }

  let resultString = result.description.trimmingCharacters(in: .newlines)
  assertStringsEqualWithDiff(resultString, expected ?? input, file: file, line: line)
}

/// A SyntaxRewriter that applies `RemoveRedundantParentheses` to all tuple expressions.
private class ParenRemovalRewriter: SyntaxRewriter {
  var unexpectedError: (any Error)?

  override func visit(_ node: TupleExprSyntax) -> ExprSyntax {
    let visited = super.visit(node)
    guard let tuple = visited.as(TupleExprSyntax.self) else {
      return visited
    }
    do {
      return try RemoveRedundantParentheses.refactor(syntax: tuple, in: ())
    } catch is RefactoringNotApplicableError {
      return ExprSyntax(tuple)
    } catch {
      unexpectedError = error
      return ExprSyntax(tuple)
    }
  }
}
