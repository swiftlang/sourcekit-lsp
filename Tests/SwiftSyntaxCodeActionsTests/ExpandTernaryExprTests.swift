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
import SwiftSyntax
import SwiftSyntaxCodeActions
import XCTest

final class ExpandTernaryExprTests: XCTestCase {
  /// Expands the expression containing the first `?` in `source` and checks the resulting source file.
  private func assertExpand(
    _ source: String,
    expected: String?,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let tree = Parser.parse(source: source)
    let questionMark = try XCTUnwrap(
      tree.tokens(viewMode: .sourceAccurate).first(where: { $0.tokenKind == .infixQuestionMark }),
      file: file,
      line: line
    )
    let expr = try XCTUnwrap(
      questionMark.ancestorOrSelf(mapping: { $0.as(SequenceExprSyntax.self) }),
      file: file,
      line: line
    )
    guard let refactored = try? ExpandTernaryExpr.refactor(syntax: ExprSyntax(expr)) else {
      if let expected {
        XCTFail("Refactoring failed, expected:\n\(expected)", file: file, line: line)
      }
      return
    }
    let utf8 = Array(source.utf8)
    let actual =
      String(decoding: utf8[..<expr.position.utf8Offset], as: UTF8.self) + refactored.description
      + String(decoding: utf8[expr.endPosition.utf8Offset...], as: UTF8.self)
    guard let expected else {
      XCTFail("Expected refactoring to fail, actual:\n\(actual)", file: file, line: line)
      return
    }
    assertStringsEqualWithDiff(actual, expected, file: file, line: line)
  }

  func testVariableInitializer() throws {
    try assertExpand(
      "let x = a < 5 ? a : b",
      expected: """
        let x = if a < 5 {
            a
        } else {
            b
        }
        """
    )
  }

  func testBaseIndentation() throws {
    try assertExpand(
      """
      func foo() {
        let x = true ? 1 : 2
        print(x)
        print(x)
      }
      """,
      expected: """
        func foo() {
          let x = if true {
            1
          } else {
            2
          }
          print(x)
          print(x)
        }
        """
    )
  }

  func testAssignment() throws {
    try assertExpand(
      "x = a ? b : c",
      expected: """
        x = if a {
            b
        } else {
            c
        }
        """
    )
  }

  func testOnlyOutermostTernaryIsExpanded() throws {
    try assertExpand(
      "let x = a ? b : c ? d : e",
      expected: """
        let x = if a {
            b
        } else {
            c ? d : e
        }
        """
    )
  }

  func testBlockComments() throws {
    try assertExpand(
      "let x = /*a*/ foo /*b*/ ? /*c*/ 1 /*d*/ : /*e*/ 2 /*f*/",
      expected: """
        let x = /*a*/ if foo /*b*/ {
            /*c*/ 1 /*d*/
        } else {
            /*e*/ 2
        } /*f*/
        """
    )
  }

  func testLineCommentBeforeTernary() throws {
    try assertExpand(
      """
      // test
      foo ? 1 : 2
      """,
      expected: """
        // test
        if foo {
            1
        } else {
            2
        }
        """
    )
  }

  func testLineCommentsInMultilineTernary() throws {
    try assertExpand(
      """
      let x = condition // why
        ? // first
          a // yes
        : b // no
      """,
      expected: """
        let x = if condition // why
        {
          // first
          a // yes
        } else {
          b
        } // no
        """
    )
  }

  func testCompoundAssignmentIsNotExpanded() throws {
    try assertExpand("x += a ? b : c", expected: nil)
  }
}
