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

final class CollapseNestedIfStmtTests: XCTestCase {
  private func assertRefactor(
    _ input: ExprSyntax,
    expected: ExprSyntax,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try SwiftSyntaxCodeActionsTests.assertRefactor(
      input,
      context: (),
      provider: CollapseNestedIfStmt.self,
      expected: expected,
      file: file,
      line: line
    )
  }

  private func assertRefactorNotApplicable(
    _ input: ExprSyntax,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try SwiftSyntaxCodeActionsTests.assertRefactor(
      input,
      context: (),
      provider: CollapseNestedIfStmt.self,
      expected: ExprSyntax?.none,
      file: file,
      line: line
    )
  }

  func testSingleConditions() throws {
    try assertRefactor(
      """
      if a > 2 {
        if a < 10 {}
      }
      """,
      expected: "if a > 2, a < 10 {}"
    )
  }

  func testMultipleConditions() throws {
    try assertRefactor(
      """
      if a > 2, a != 4 {
        if a < 10, a != 5 {}
      }
      """,
      expected: "if a > 2, a != 4, a < 10, a != 5 {}"
    )
  }

  func testOptionalBinding() throws {
    try assertRefactor(
      """
      if let b = a {
        if b != 5 {}
      }
      """,
      expected: "if let b = a, b != 5 {}"
    )
  }

  func testCasePattern() throws {
    try assertRefactor(
      """
      if case .some(let b) = a {
        if b != 5 {}
      }
      """,
      expected: "if case .some(let b) = a, b != 5 {}"
    )
  }

  func testAvailabilityCondition() throws {
    try assertRefactor(
      """
      if #available(macOS 15, *) {
        if let b = a {}
      }
      """,
      expected: "if #available(macOS 15, *), let b = a {}"
    )
  }

  func testBodyIsUnindented() throws {
    try assertRefactor(
      """
      if a {
        if b {
          foo()
          if c {
            bar()
          }
        }
      }
      """,
      expected: """
        if a, b {
          foo()
          if c {
            bar()
          }
        }
        """
    )
  }

  func testBodyIsUnindentedByIndentationDifferenceOfStatements() throws {
    try assertRefactor(
      """
      if a {
          if b {
              foo()
          }
      }
      """,
      expected: """
        if a, b {
            foo()
        }
        """
    )
  }

  func testMultilineStringLiteralInBodyIsUnindentedConsistently() throws {
    try assertRefactor(
      #"""
      if a {
        if b {
          print("""
            hello
              world
            """)
        }
      }
      """#,
      expected: #"""
        if a, b {
          print("""
            hello
              world
            """)
        }
        """#
    )
  }

  func testSingleLine() throws {
    try assertRefactor(
      "if a { if b { foo() } }",
      expected: "if a, b { foo() }"
    )
  }

  func testSingleLineNestedIfOnSeparateLine() throws {
    try assertRefactor(
      """
      if a {
        if b { foo() }
      }
      """,
      expected: "if a, b { foo() }"
    )
  }

  func testBracesOnSeparateLines() throws {
    try assertRefactor(
      """
      if a
      {
        if b
        {
          foo()
        }
      }
      """,
      expected: """
        if a, b
        {
          foo()
        }
        """
    )
  }

  func testMultilineConditions() throws {
    try assertRefactor(
      """
      if let a,
        let b
      {
        if let c,
          let d
        {
          foo()
        }
      }
      """,
      expected: """
        if let a,
          let b, let c,
          let d
        {
          foo()
        }
        """
    )
  }

  func testIndentationIsNotAffectedByCommentsBeforeIfStatements() throws {
    try assertRefactor(
      """
      // outer
        if a { // a
          if b {
            foo()
          }
        }
      """,
      expected: """
        // outer
          if a, b { // a
            foo()
          }
        """
    )
  }

  func testOnlyCollapsesOneLevel() throws {
    try assertRefactor(
      """
      if a {
        if b {
          if c {
            foo()
          }
        }
      }
      """,
      expected: """
        if a, b {
          if c {
            foo()
          }
        }
        """
    )
  }

  func testCommentsInConditionsAreKept() throws {
    try assertRefactor(
      """
      if a /* a */ {
        if /* b */ b {}
      }
      """,
      expected: "if a, /* a */ /* b */ b {}"
    )
  }

  func testCommentBeforeNestedIfIsMovedIntoBody() throws {
    try assertRefactor(
      """
      if let user {
        // Only admins may do this.
        if user.isAdmin {
          deleteEverything()
        }
      }
      """,
      expected: """
        if let user, user.isAdmin {
          // Only admins may do this.
          deleteEverything()
        }
        """
    )
  }

  func testCommentAfterNestedIfIsMovedIntoBody() throws {
    try assertRefactor(
      """
      if a {
        if b {
          foo()
          // end of b
        }
        // end of a
      }
      """,
      expected: """
        if a, b {
          foo()
          // end of b
          // end of a
        }
        """
    )
  }

  func testTrailingCommentsOnBracesAreKept() throws {
    try assertRefactor(
      """
      if a { // a
        if b { // b
          foo()
        } // end b
      } // end a
      """,
      expected: """
        if a, b { // b // a
          foo()
          // end b
        } // end a
        """
    )
  }

  func testCommentBeforeNestedIfWithSingleLineBody() throws {
    try assertRefactor(
      """
      if a {
        // comment
        if b { foo() }
      }
      """,
      expected: """
        if a, b {
          // comment
          foo() }
        """
    )
  }

  func testCommentBeforeNestedIfWithEmptyBody() throws {
    try assertRefactor(
      """
      if a {
        // comment
        if b {}
      }
      """,
      expected: """
        if a, b {
          // comment
        }
        """
    )
  }

  func testLineCommentBeforeOuterBodyDoesNotSwallowCondition() throws {
    try assertRefactor(
      """
      if a // a
      {
        if b {}
      }
      """,
      expected: """
        if a, // a
        b {}
        """
    )
  }

  func testOuterIfWithElseIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        if b {}
      } else {
        foo()
      }
      """
    )
  }

  func testNestedIfWithElseIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        if b {
          foo()
        } else {
          bar()
        }
      }
      """
    )
  }

  func testNestedIfWithElseIfIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        if b {
          foo()
        } else if c {
          bar()
        }
      }
      """
    )
  }

  func testBodyWithMultipleStatementsIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        foo()
        if b {
          bar()
        }
      }
      """
    )
    try assertRefactorNotApplicable(
      """
      if a {
        if b {
          bar()
        }
        foo()
      }
      """
    )
  }

  func testBodyWithoutNestedIfIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        foo()
      }
      """
    )
    try assertRefactorNotApplicable("if a {}")
    try assertRefactorNotApplicable(
      """
      if a {
        while b {}
      }
      """
    )
  }

  func testLabeledNestedIfIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        inner: if b {
          break inner
        }
      }
      """
    )
  }

  func testNestedIfInIfConfigIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        #if DEBUG
        if b {}
        #endif
      }
      """
    )
  }

  func testIfWithSyntaxErrorIsNotCollapsed() throws {
    try assertRefactorNotApplicable(
      """
      if a {
        if b {
          foo(
        }
      }
      """
    )
  }
}
