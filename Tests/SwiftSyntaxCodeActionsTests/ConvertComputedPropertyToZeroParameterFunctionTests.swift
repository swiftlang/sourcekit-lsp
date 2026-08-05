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

final class ConvertComputedPropertyToZeroParameterFunctionTests: XCTestCase {
  func testRefactoringComputedPropertyToFunction() throws {
    let baseline: DeclSyntax = """
      var asJSON: String { "" }
      """

    let expected: DeclSyntax = """
      func asJSON() -> String { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithVoidToFunction() throws {
    let baseline: DeclSyntax = """
      var asJSON: Void { () }
      """

    let expected: DeclSyntax = """
      func asJSON() { () }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithTupleToFunction() throws {
    let baseline: DeclSyntax = """
      var asJSON: (String, String) { ("", "") }
      """

    let expected: DeclSyntax = """
      func asJSON() -> (String, String) { ("", "") }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithClosureToFunction() throws {
    let baseline: DeclSyntax = """
      var asJSON: () -> Void { {} }
      """

    let expected: DeclSyntax = """
      func asJSON() -> () -> Void { {} }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithClosureToFunction2() throws {
    let baseline: DeclSyntax = """
      var asJSON: () -> () { {} }
      """

    let expected: DeclSyntax = """
      func asJSON() -> () -> () { {} }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithVoidToFunctionWithSeparatingComment() throws {
    let baseline: DeclSyntax = """
      var  asJSON  :  /*comment*/ Void {  ()  }
      """

    let expected: DeclSyntax = """
      func  asJSON()    /*comment*/ {  ()  }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyToFunctionWithReturnStmt() throws {
    let baseline: DeclSyntax = """
      var asJSON: String { return "" }
      """

    let expected: DeclSyntax = """
      func asJSON() -> String { return "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyToFunctionWithModifiers() throws {
    let baseline: DeclSyntax = """
      static var  asJSON: String { "" }
      """

    let expected: DeclSyntax = """
      static func  asJSON() -> String { "" }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyToFunctionWithMultipleStms() throws {
    let baseline: DeclSyntax = """
      var  asJSON: String {
        let builder = JSONBuilder()
        return builder.convert()
      }
      """

    let expected: DeclSyntax = """
      func  asJSON() -> String {
        let builder = JSONBuilder()
        return builder.convert()
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyToFunctionWithCommentsAndIndentations() throws {
    let baseline: DeclSyntax = """
        static  var  asJSON  :  String  {  /*comment*/ ""  /*comment*/  }
      """

    let expected: DeclSyntax = """
        static  func  asJSON()   ->  String  {  /*comment*/ ""  /*comment*/  }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyToFunctionWithComments() throws {
    let baseline: DeclSyntax = """
      // Comment
        public static  var  asJSON  :  String  { /*comment*/
        /*comment*/ return "String"
      // Some documentation
      } // Comment
      """

    let expected: DeclSyntax = """
      // Comment
        public static  func  asJSON()   ->  String  { /*comment*/
        /*comment*/ return "String"
      // Some documentation
      } // Comment
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyToNothing() throws {
    let baseline: DeclSyntax = """
      var x: Int {
          get { 5 }
          set { /*anything */ }
      }
      """
    try assertRefactorConvert(baseline, expected: nil)
  }

  func testRefactoringComputedPropertyWithGetAccessorToFunction() throws {
    let baseline: DeclSyntax = """
      var x: Int {
        get { 5 }
      }
      """

    let expected: DeclSyntax = """
      func x() -> Int {
        5
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithGetAccessorAndAsyncEffectSpecifierToFunction() throws {
    let baseline: DeclSyntax = """
      var foo: Int {
        get async { await someAsyncValue() }
      }

      """

    let expected: DeclSyntax = """
      func foo() async -> Int {
        await someAsyncValue()
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithGetAccessorAndThrowsEffectSpecifierToFunction() throws {
    let baseline: DeclSyntax = """
      var foo: Int {
        get throws { someAsyncValue() }
      }
      """

    let expected: DeclSyntax = """
      func foo() throws -> Int {
        someAsyncValue()
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithGetAccessorAndAsyncThrowsEffectSpecifierToFunction() throws {
    let baseline: DeclSyntax = """
      var foo: Int {
        get async throws { someAsyncValue() }
      }
      """

    let expected: DeclSyntax = """
      func foo() async throws -> Int {
        someAsyncValue()
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithLeadingTriviaInBindingToFunction() throws {
    let baseline: DeclSyntax = """
      /// Documented behavior
      var foo: Int { 0 }
      """

    let expected: DeclSyntax = """
      /// Documented behavior
      func foo() -> Int { 0 }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithAccessorCommentsToFunction() throws {
    let baseline: DeclSyntax = """
      var foo: Int {
        get /*docs...*/ { 0 }
      }
      """

    let expected: DeclSyntax = """
      func foo() -> Int {
        /*docs...*/ 0
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithCommentsInsideAccessorToFunction() throws {
    let baseline: DeclSyntax = """
      var foo: Int {
        get { /*docs*/ 0 /*documented*/ }
      }
      """

    let expected: DeclSyntax = """
      func foo() -> Int {
        /*docs*/ 0 /*documented*/
      }
      """

    try assertRefactorConvert(baseline, expected: expected)
  }

  func testRefactoringComputedPropertyWithAccessorMultipleCommentsToFunction() throws {
    let baseline: DeclSyntax = """
      var foo: Int { // Leading comments
        get /*docs...*/ { 0 } // docs
      /*Trailing Comments*/ }
      """

    let expected: DeclSyntax = """
      func foo() -> Int { // Leading comments
        /*docs...*/ 0 // docs
      /*Trailing Comments*/ }
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
    provider: ConvertComputedPropertyToZeroParameterFunction.self,
    expected: expected,
    file: file,
    line: line
  )
}
