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
import SwiftSyntaxBuilder
import SwiftSyntaxCodeActions
import XCTest

final class InvertIfConditionTests: XCTestCase {
  private func assertRefactor(
    _ input: ExprSyntax,
    expected: ExprSyntax,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try SwiftSyntaxCodeActionsTests.assertRefactor(
      input,
      context: (),
      provider: InvertIfCondition.self,
      expected: expected,
      file: file,
      line: line
    )
  }

  private func assertRefactorFails(
    _ input: ExprSyntax,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try SwiftSyntaxCodeActionsTests.assertRefactor(
      input,
      context: (),
      provider: InvertIfCondition.self,
      expected: ExprSyntax?.none,
      file: file,
      line: line
    )
  }

  func testInvertIfCondition() throws {
    // Negated identifier
    try assertRefactor(
      """
      if !x {
        foo()
      } else {
        bar()
      }
      """,
      expected: """
        if x {
          bar()
        } else {
          foo()
        }
        """
    )

    // Negated comparison with redundant parentheses removed
    try assertRefactor(
      """
      if !(x == y) {
        return
      } else {
        continue
      }
      """,
      expected: """
        if x == y {
          continue
        } else {
          return
        }
        """
    )

    // Leading comment before condition
    try assertRefactor(
      """
      if /* comment */ !x {
        a
      } else {
        b
      }
      """,
      expected: """
        if /* comment */ x {
          b
        } else {
          a
        }
        """
    )

    // Trailing comment after condition
    try assertRefactor(
      """
      if !x /* comment */ {
        a
      } else {
        b
      }
      """,
      expected: """
        if x /* comment */ {
          b
        } else {
          a
        }
        """
    )

    // Comment inside negated condition with redundant parentheses removed
    try assertRefactor(
      """
      if !(/* comment */ x == y) {
        return
      } else {
        continue
      }
      """,
      expected: """
        if /* comment */ x == y {
          continue
        } else {
          return
        }
        """
    )

    // Comments in bodies preserved
    try assertRefactor(
      """
      if !x {
        // body comment
        foo()
      } else {
        // else comment
        bar()
      }
      """,
      expected: """
        if x {
          // else comment
          bar()
        } else {
          // body comment
          foo()
        }
        """
    )

    // Non-negated identifier
    try assertRefactor(
      """
      if x {
        a
      } else {
        b
      }
      """,
      expected: """
        if !x {
          b
        } else {
          a
        }
        """
    )

    // Non-negated equality comparison (becomes !=)
    try assertRefactor(
      """
      if x == y {
        a
      } else {
        b
      }
      """,
      expected: """
        if x != y {
          b
        } else {
          a
        }
        """
    )

    // Non-negated inequality comparison (becomes ==)
    try assertRefactor(
      """
      if x != y {
        a
      } else {
        b
      }
      """,
      expected: """
        if x == y {
          b
        } else {
          a
        }
        """
    )

    // Non-negated less than comparison (becomes >=)
    try assertRefactor(
      """
      if x < y {
        a
      } else {
        b
      }
      """,
      expected: """
        if x >= y {
          b
        } else {
          a
        }
        """
    )

    // Conjunction (De Morgan's law: !(a && b) -> !a || !b)
    try assertRefactor(
      """
      if a && b {
        foo()
      } else {
        bar()
      }
      """,
      expected: """
        if !a || !b {
          bar()
        } else {
          foo()
        }
        """
    )

    // Disjunction (De Morgan's law: !(a || b) -> !a && !b)
    try assertRefactor(
      """
      if a || b {
        foo()
      } else {
        bar()
      }
      """,
      expected: """
        if !a && !b {
          bar()
        } else {
          foo()
        }
        """
    )

    // Function call
    try assertRefactor(
      """
      if foo() {
        a
      } else {
        b
      }
      """,
      expected: """
        if !foo() {
          b
        } else {
          a
        }
        """
    )

    // Parenthesized identifier
    try assertRefactor(
      """
      if (x) {
        a
      } else {
        b
      }
      """,
      expected: """
        if !x {
          b
        } else {
          a
        }
        """
    )
  }

  func testInvertIfConditionFails() throws {
    // No else
    try assertRefactorFails(
      """
      if !x {
        a
      }
      """
    )

    try assertRefactorFails(
      """
      if x {
        a
      }
      """
    )

    // Else if (not a CodeBlock)
    try assertRefactorFails(
      """
      if !x {
        a
      } else if y {
        b
      }
      """
    )

    // Multiple conditions
    try assertRefactorFails(
      """
      if !x, !y {
        a
      } else {
        b
      }
      """
    )

    try assertRefactorFails(
      """
      if x, y {
        a
      } else {
        b
      }
      """
    )

    // Binding
    try assertRefactorFails(
      """
      if let x = y {
        a
      } else {
        b
      }
      """
    )

    // Case condition
    try assertRefactorFails(
      """
      if case .foo = x {
        a
      } else {
        b
      }
      """
    )
  }
}
