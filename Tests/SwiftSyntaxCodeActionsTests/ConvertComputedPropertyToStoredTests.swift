//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
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

final class ConvertComputedPropertyToStoredTests: XCTestCase {
  func testToStored() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color { Color() /* some text */ }
      """

    let expected: DeclSyntax = """
      let defaultColor: Color = Color() /* some text */
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testToStoredWithReturnStatement() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color {
        return Color()
      }
      """

    let expected: DeclSyntax = """
      let defaultColor: Color = Color()
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testToStoredWithReturnStatementAndTrailingComment() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color {
        return Color() /* some text */
      }
      """

    let expected: DeclSyntax = """
      let defaultColor: Color = Color() /* some text */
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testToStoredWithReturnStatementAndTrailingCommentOnNewLine() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color {
        return Color()
        /* some text */
      }
      """

    let expected: DeclSyntax = """
      let defaultColor: Color = Color()
        /* some text */
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testToStoredWithMultipleStatementsInAccessor() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color {
        let color = Color()
        return color
      }
      """

    let expected: DeclSyntax = """
      let defaultColor: Color = {
        let color = Color()
        return color
      }()
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testToStoredWithMultipleStatementsInAccessorAndTrailingCommentsOnNewLine() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color {
        let color = Color()
        return color
        // returns color
      }
      """

    let expected: DeclSyntax = """
      let defaultColor: Color = {
        let color = Color()
        return color
        // returns color
      }()
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testToStoredWithMultipleStatementsInAccessorAndLeadingComments() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color { // returns color
        let color = Color()
        return color
      }
      """

    let expected: DeclSyntax = """
      let defaultColor: Color = { // returns color
        let color = Color()
        return color
      }()
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testToStoreWithSeparatingComments() throws {
    let baseline: DeclSyntax = """
      var x: Int {
        return
        /* One */ 1
      }
      """

    let expected: DeclSyntax = """
      let x: Int =
        /* One */ 1
      """

    try assertRefactorConvert(baseline, expected: expected)
  }
}

private func assertRefactorConvert(
  _ callDecl: DeclSyntax,
  expected: DeclSyntax?,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  try assertRefactor(
    callDecl,
    context: (),
    provider: ConvertComputedPropertyToStored.self,
    expected: expected,
    file: file,
    line: line
  )
}
