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

final class ConvertStoredPropertyToComputedTests: XCTestCase {
  func testRefactoringStoredPropertyWithInitializer1() throws {
    let baseline: DeclSyntax = """
      static let defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      static var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializer1AndLeadingComments() throws {
    let baseline: DeclSyntax = """
      static let defaultColor: Color = /* red */ .red
      """

    let expected: DeclSyntax = """
      static var defaultColor: Color { /* red */ .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializer1AndLeadingComments2() throws {
    let baseline: DeclSyntax = """
      static let defaultColor: Color = 
        /* red */ .red
      """

    let expected: DeclSyntax = """
      static var defaultColor: Color { 
        /* red */ .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializer1AndTrailingComments() throws {
    let baseline: DeclSyntax = """
      static let defaultColor: Color = .red /* red */
      """

    let expected: DeclSyntax = """
      static var defaultColor: Color { .red /* red */ }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializer1AndTrailingComments2() throws {
    let baseline: DeclSyntax = """
      static let defaultColor: Color = .red
        /* red */
      """

    let expected: DeclSyntax = """
      static var defaultColor: Color { .red
        /* red */ }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializerAndComments() throws {
    let baseline: DeclSyntax = """
      static /* one */ let defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      static /* one */ var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializerAndCommentsInBinding() throws {
    let baseline: DeclSyntax = """
      static let /* binding */ defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      static var /* binding */ defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializer2() throws {
    let baseline: DeclSyntax = """
      static let defaultColor: Color = Color.red
      """

    let expected: DeclSyntax = """
      static var defaultColor: Color { Color.red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializer3() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color = Color.red
      """

    let expected: DeclSyntax = """
      var defaultColor: Color { Color.red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithInitializer4() throws {
    let baseline: DeclSyntax = """
      var defaultColor: Color = Color()
      """

    let expected: DeclSyntax = """
      var defaultColor: Color { Color() }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithMultipleStatements() throws {
    let baseline: DeclSyntax = """
      var three: Int = {
        let one = 1
        let two = 2
        return 1 + 2
      }()
      """

    let expected: DeclSyntax = """
      var three: Int {
        let one = 1
        let two = 2
        return 1 + 2
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithFunctionCallAndArguments() throws {
    let baseline: DeclSyntax = """
      let myVar = { value in
        return value
      }(1)
      """

    try assertRefactorConvert(baseline, expected: nil)
  }

  func testRefactoringStoredPropertyWithLazyKeyword() throws {
    let baseline: DeclSyntax = """
      lazy var defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithModifiers() throws {
    let baseline: DeclSyntax = """
      private lazy var defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      private var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithModifiers2() throws {
    let baseline: DeclSyntax = """
      lazy private var defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      private var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithModifiersAndComment() throws {
    let baseline: DeclSyntax = """
      lazy /* some comment */ private var defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      /* some comment */ private var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithModifiersAndComment2() throws {
    let baseline: DeclSyntax = """
      private /* comment */ lazy var defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      private /* comment */ var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithModifierAndComment() throws {
    let baseline: DeclSyntax = """
      lazy /* comment */ var defaultColor: Color = .red
      """

    let expected: DeclSyntax = """
      /* comment */ var defaultColor: Color { .red }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStructStoredPropertiyWithModifiers() throws {
    let baseline: DeclSyntax = """
      struct Foo {
        lazy private var defaultColor: Color = .red
      }
      """

    let expected: DeclSyntax = """
      struct Foo {
        private var defaultColor: Color { .red }
      }
      """

    try assertRefactorStructConvert(baseline, expected: expected)
  }

  func testRefactoringStructStoredPropertiyWithModifiers2() throws {
    let baseline: DeclSyntax = """
      struct Foo {
        private
        /* comment */ lazy var defaultColor: Color = .red
      }
      """

    let expected: DeclSyntax = """
      struct Foo {
        private
        /* comment */ var defaultColor: Color { .red }
      }
      """

    try assertRefactorStructConvert(baseline, expected: expected)
  }

  func testRefactoringStructStoredPropertiyWithModifiers3() throws {
    let baseline: DeclSyntax = """
      struct Foo {
        private /* comment */
        /* another comment */ lazy var defaultColor: Color = .red
      }
      """

    let expected: DeclSyntax = """
      struct Foo {
        private /* comment */
        /* another comment */ var defaultColor: Color { .red }
      }
      """

    try assertRefactorStructConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyMissingTypeAnnotation() throws {
    let baseline: DeclSyntax = "var foo = \"abc\""
    let expected: DeclSyntax = "var foo: <#Type#>{ \"abc\" }"

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringStoredPropertyWithTypeAnnotation() throws {
    let baseline: DeclSyntax = "var foo = \"abc\""
    let expected: DeclSyntax = "var foo: String{ \"abc\" }"

    let context = ConvertStoredPropertyToComputed.Context(type: TypeSyntax(stringLiteral: "String"))
    try assertRefactorConvert(baseline, expected: expected, context: context)
  }
}

private func assertRefactorConvert(
  _ callDecl: DeclSyntax,
  expected: DeclSyntax?,
  context: ConvertStoredPropertyToComputed.Context = .init(),
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  try assertRefactor(
    callDecl,
    context: context,
    provider: ConvertStoredPropertyToComputed.self,
    expected: expected,
    file: file,
    line: line
  )
}

private func assertRefactorStructConvert(
  _ callDecl: DeclSyntax,
  expected: DeclSyntax,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {

  let structCallDecl = try XCTUnwrap(callDecl.as(StructDeclSyntax.self))
  let variable = try XCTUnwrap(structCallDecl.memberBlock.members.first?.decl.as(VariableDeclSyntax.self))
  let refactored = try ConvertStoredPropertyToComputed.refactor(
    syntax: variable,
    in: ConvertStoredPropertyToComputed.Context()
  )

  let members = MemberBlockItemListSyntax {
    MemberBlockItemSyntax(decl: DeclSyntax(refactored))
  }

  let refactoredMemberBlock = structCallDecl.memberBlock.with(\.members, members)
  let refactoredStruct = structCallDecl.with(\.memberBlock, refactoredMemberBlock)
  assertStringsEqualWithDiff(refactoredStruct.description, expected.description)
}
