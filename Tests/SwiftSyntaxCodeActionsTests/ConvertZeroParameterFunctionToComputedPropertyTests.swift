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

final class ConvertZeroParameterFunctionToComputedPropertyTests: XCTestCase {
  func testRefactoringFunctionToComputedProperty() throws {
    let baseline: DeclSyntax = """
      func asJSON() -> String { "" }
      """

    let expected: DeclSyntax = """
      var asJSON: String { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyPreservesLeadingComment() throws {
    try assertRefactorConvert(
      """
      /// Some comment
      func asJSON() -> String { "" }
      """,
      expected: """
        /// Some comment
        var asJSON: String { "" }
        """
    )

    // With a modifier (comment is leading trivia of the modifier).
    try assertRefactorConvert(
      """
      /// Some comment
      public func asJSON() -> String { "" }
      """,
      expected: """
        /// Some comment
        public var asJSON: String { "" }
        """
    )

    // With an attribute (comment is leading trivia of the attribute).
    try assertRefactorConvert(
      """
      /// Some comment
      @inlinable func asJSON() -> String { "" }
      """,
      expected: """
        /// Some comment
        @inlinable var asJSON: String { "" }
        """
    )

    // Block doc comment.
    try assertRefactorConvert(
      """
      /** Some comment */
      func asJSON() -> String { "" }
      """,
      expected: """
        /** Some comment */
        var asJSON: String { "" }
        """
    )
  }

  func testRefactoringFunctionToComputedPropertyWithVoidType() throws {
    let baseline: DeclSyntax = """
      func asJSON() { () }
      """

    let expected: DeclSyntax = """
      var asJSON: Void { () }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithTuple() throws {
    let baseline: DeclSyntax = """
      func asJSON() -> (String, String) { ("", "") }
      """

    let expected: DeclSyntax = """
      var asJSON: (String, String) { ("", "") }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithClosure() throws {
    let baseline: DeclSyntax = """
      func asJSON() -> () -> Void { {} }
      """

    let expected: DeclSyntax = """
      var asJSON: () -> Void { {} }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithModifiers() throws {
    let baseline: DeclSyntax = """
      static func  asJSON() -> String  { "" }
      """

    let expected: DeclSyntax = """
      static var  asJSON: String  { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithModifiersAndIndentations() throws {
    let baseline: DeclSyntax = """
        static  func  asJSON()  ->  String  { "" }
      """

    let expected: DeclSyntax = """
        static  var  asJSON:  String  { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithModifiersAndComments() throws {
    let baseline: DeclSyntax = """
      static func asJSON() -> String { // comment
      /*comment*/ "" /*comment*/
      } // comment
      """

    let expected: DeclSyntax = """
      static var asJSON: String { // comment
      /*comment*/ "" /*comment*/
      } // comment
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithReturnStms() throws {
    let baseline: DeclSyntax = """
      static  func  asJSON()  ->  String  {
        return ""
      }
      """

    let expected: DeclSyntax = """
      static  var  asJSON:  String  {
        return ""
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithMultipleStms() throws {
    let baseline: DeclSyntax = """
      static  func  asJSON()  ->  String  {
        let builder = JSONBuilder()
        return builder.convert()
      }
      """

    let expected: DeclSyntax = """
      static  var  asJSON:  String  {
        let builder = JSONBuilder()
        return builder.convert()
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyPreservesBlockComment() throws {
    let baseline: DeclSyntax = """
      /* Block comment */
      func asJSON() -> String { "" }
      """

    let expected: DeclSyntax = """
      /* Block comment */
      var asJSON: String { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyPreservesDocComment() throws {
    let baseline: DeclSyntax = """
      /// Documentation comment
      public static func asJSON() -> String { "" }
      """

    let expected: DeclSyntax = """
      /// Documentation comment
      public static var asJSON: String { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }
  func testRefactoringFunctionToComputedPropertyWithAttributes() throws {
    let baseline: DeclSyntax = """
      @available(*, deprecated, message: "Use the property instead")
      func asJSON() -> String { "" }
      """

    let expected: DeclSyntax = """
      @available(*, deprecated, message: "Use the property instead")
      var asJSON: String { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringFunctionToComputedPropertyWithMidTrivia() throws {
    let baseline: DeclSyntax = """
      func /* comment */ asJSON() -> String { "" }
      """

    let expected: DeclSyntax = """
      var /* comment */ asJSON: String { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testAsyncThrowsFunction() throws {
    let baseline: DeclSyntax = """
      func foo() async throws -> Int {
        try await someCall()
      }
      """

    let expected: DeclSyntax = """
      var foo: Int {
        get async throws {
          try await someCall()
        }
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testAsyncOnlyFunction() throws {
    let baseline: DeclSyntax = """
      func bar() async -> String {
        await getValue()
      }
      """

    let expected: DeclSyntax = """
      var bar: String {
        get async {
          await getValue()
        }
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testThrowsOnlyFunction() throws {
    let baseline: DeclSyntax = """
      func baz() throws -> Bool {
        try riskyOperation()
      }
      """

    let expected: DeclSyntax = """
      var baz: Bool {
        get throws {
          try riskyOperation()
        }
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testSynchronousFunction() throws {
    let baseline: DeclSyntax = """
      func qux() -> Int {
        return 42
      }
      """

    let expected: DeclSyntax = """
      var qux: Int {
        return 42
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testAsyncFunctionWithMultiLineStatement() throws {
    let baseline: DeclSyntax = """
      func foo() async {
        bar(
          1
        )
      }
      """

    let expected: DeclSyntax = """
      var foo: Void {
        get async {
          bar(
            1
          )
        }
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testAsyncThrowsFunctionWithMultipleStatements() throws {
    let baseline: DeclSyntax = """
      func complex() async throws -> String {
        let x = try await fetch()
        let y = process(x)
        return y
      }
      """

    let expected: DeclSyntax = """
      var complex: String {
        get async throws {
          let x = try await fetch()
          let y = process(x)
          return y
        }
      }
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
    provider: ConvertZeroParameterFunctionToComputedProperty.self,
    expected: expected,
    file: file,
    line: line
  )
}
