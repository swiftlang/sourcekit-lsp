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
  func testInvertIfCondition() throws {
    let tests: [(ExprSyntax, ExprSyntax)] = [
      (
        """
        if !x {
          foo()
        } else {
          bar()
        }
        """,
        """
        if x {
          bar()
        } else {
          foo()
        }
        """
      ),
      (
        """
        if !(x == y) {
          return
        } else {
          continue
        }
        """,
        """
        if (x == y) {
          continue
        } else {
          return
        }
        """
      ),
      (
        """
        if /* comment */ !x {
          a
        } else {
          b
        }
        """,
        """
        if /* comment */ x {
          b
        } else {
          a
        }
        """
      ),
      (
        """
        if !x /* comment */ {
          a
        } else {
          b
        }
        """,
        """
        if x /* comment */ {
          b
        } else {
          a
        }
        """
      ),
      (
        """
        if !(/* comment */ x == y) {
          return
        } else {
          continue
        }
        """,
        """
        if (/* comment */ x == y) {
          continue
        } else {
          return
        }
        """
      ),
      (
        """
        if !x {
          // body comment
          foo()
        } else {
          // else comment
          bar()
        }
        """,
        """
        if x {
          // else comment
          bar()
        } else {
          // body comment
          foo()
        }
        """
      ),
    ]

    for (input, expected) in tests {
      try assertRefactor(input, context: (), provider: InvertIfCondition.self, expected: expected)
    }
  }

  func testInvertIfConditionFails() throws {
    let tests: [ExprSyntax] = [
      // Not negated
      """
      if x {
        a
      } else {
        b
      }
      """,
      // No else
      """
      if !x {
        a
      }
      """,
      // Else if (not a CodeBlock)
      """
      if !x {
        a
      } else if y {
        b
      }
      """,
      // Multiple conditions
      """
      if !x, !y {
        a
      } else {
        b
      }
      """,
      // Binding
      """
      if let x = y {
        a
      } else {
        b
      }
      """,
    ]

    for input in tests {
      try assertRefactor(input, context: (), provider: InvertIfCondition.self, expected: ExprSyntax?.none)
    }
  }
}
