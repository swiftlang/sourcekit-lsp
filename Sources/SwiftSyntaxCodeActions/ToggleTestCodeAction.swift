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

internal import LanguageServerProtocol
internal import SourceKitLSP
import SwiftBasicFormat
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder

struct ToggleTestCodeAction: SyntaxRefactoringCodeActionProvider {

  package static let title: String = "Toggle Test Enabled/Disabled"

  package static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> FunctionDeclSyntax? {

    guard
      let function = scope.innermostNodeContainingRange?.findParentOfSelf(
        ofType: FunctionDeclSyntax.self,
        stoppingIf: { _ in false }
      )
    else {
      return nil
    }

    guard findTestAttribute(in: function) != nil || isXCTestFunction(function) else {
      return nil
    }

    return function
  }

  package static func textRefactor(syntax function: FunctionDeclSyntax, in context: Void) throws -> [SourceEdit] {
    let refactoredFunction: FunctionDeclSyntax

    // Route to the appropriate toggling logic based on which test framework is detected.
    if let (index, testAttribute) = findTestAttribute(in: function) {
      refactoredFunction = toggleSwiftTestingTest(
        function: function,
        attributeIndex: index,
        testAttribute: testAttribute
      )
    } else if isXCTestFunction(function) {
      refactoredFunction = toggleXCTest(function: function)
    } else {
      throw RefactoringNotApplicableError("Function is not a recognized test")
    }

    let editRange = function.position..<function.endPosition

    return [
      SourceEdit(
        range: editRange,
        replacement: refactoredFunction.description
      )
    ]
  }

  private static func findTestAttribute(in function: FunctionDeclSyntax) -> (Int, AttributeSyntax)? {
    let attributesArray = Array(function.attributes)

    for (index, element) in attributesArray.enumerated() {
      guard case .attribute(let attr) = element else { continue }

      let name = attr.attributeName.trimmedDescription
      if name == "Test" || name == "Testing.Test" {
        return (index, attr)
      }
    }
    return nil
  }

  private static func toggleSwiftTestingTest(
    function: FunctionDeclSyntax,
    attributeIndex: Int,
    testAttribute: AttributeSyntax
  ) -> FunctionDeclSyntax {
    var newFunction = function
    var newAttribute = testAttribute
    var argumentsList = LabeledExprListSyntax([])

    if case .argumentList(let exprList) = testAttribute.arguments {
      argumentsList = exprList
    }

    var argumentsArray = Array(argumentsList)

    // Check if the `.disabled(...)` trait is already present in the arguments.
    if let disabledArgIndex = argumentsArray.firstIndex(where: { isDisabledTrait($0.expression) }) {

      // The test is currently disabled, so enable it by removing the trait.
      argumentsArray.remove(at: disabledArgIndex)

      if !argumentsArray.isEmpty, disabledArgIndex == argumentsArray.count {
        argumentsArray[argumentsArray.count - 1].trailingComma = nil
      }

      if argumentsArray.isEmpty {
        newAttribute.leftParen = nil
        newAttribute.arguments = nil
        newAttribute.rightParen = nil
      } else {
        newAttribute.arguments = .argumentList(LabeledExprListSyntax(argumentsArray))
      }
    } else {

      // The test is currently enabled, so disable it by appending the `.disabled()` trait.
      let disabledExpr = ExprSyntax(
        MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier("disabled")))
      )
      let functionCall = FunctionCallExprSyntax(
        calledExpression: disabledExpr,
        leftParen: .leftParenToken(),
        arguments: [],
        rightParen: .rightParenToken()
      )

      if !argumentsArray.isEmpty {
        argumentsArray[argumentsArray.count - 1].trailingComma = .commaToken(trailingTrivia: .space)
      }

      argumentsArray.append(LabeledExprSyntax(expression: ExprSyntax(functionCall)))

      newAttribute.leftParen = testAttribute.leftParen ?? .leftParenToken()
      newAttribute.arguments = .argumentList(LabeledExprListSyntax(argumentsArray))
      newAttribute.rightParen = testAttribute.rightParen ?? .rightParenToken()
    }

    var attributesArray = Array(function.attributes)
    attributesArray[attributeIndex] = .attribute(newAttribute)
    newFunction.attributes = AttributeListSyntax(attributesArray)

    return newFunction.formatted().as(FunctionDeclSyntax.self) ?? newFunction
  }

  private static func isDisabledTrait(_ expr: ExprSyntax) -> Bool {
    guard let functionCall = expr.as(FunctionCallExprSyntax.self),
      let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self)
    else {
      return false
    }
    return memberAccess.declName.baseName.text == "disabled"
  }

  private static func isXCTestFunction(_ function: FunctionDeclSyntax) -> Bool {
    let name = function.name.text

    guard name.hasPrefix("test"), name.count > 4 else {
      return false
    }

    let indexAfterTest = name.index(name.startIndex, offsetBy: 4)
    let nextChar = name[indexAfterTest]
    guard nextChar.isUppercase || nextChar.isNumber || nextChar == "_" else {
      return false
    }

    let hasNoParams = function.signature.parameterClause.parameters.isEmpty
    let hasNoReturnType = function.signature.returnClause == nil
    let isNotStaticOrClass = !function.modifiers.contains { modifier in
      let kind = modifier.name.tokenKind
      return kind == .keyword(.static) || kind == .keyword(.class)
    }

    return hasNoParams && hasNoReturnType && isNotStaticOrClass
  }

  private static func toggleXCTest(function: FunctionDeclSyntax) -> FunctionDeclSyntax {
    guard let body = function.body else { return function }

    var newFunction = function
    var statementsArray = Array(body.statements)

    if let skipIndex = statementsArray.firstIndex(where: isXCTSkipStatement) {
      statementsArray.remove(at: skipIndex)

      // Remove `throws` only if the remaining body no longer requires it.
      let remainingBody = CodeBlockSyntax(statements: CodeBlockItemListSyntax(statementsArray.map { $0.trimmed }))
      if !bodyRequiresThrows(remainingBody) {
        newFunction.signature.effectSpecifiers?.throwsClause = nil

        if newFunction.signature.effectSpecifiers?.asyncSpecifier == nil {
          newFunction.signature.effectSpecifiers = nil
        }
      }
    } else {
      let skipString = StringLiteralExprSyntax(content: "Disabled")
      let skipCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("XCTSkip")),
        leftParen: .leftParenToken(),
        arguments: [LabeledExprSyntax(expression: ExprSyntax(skipString))],
        rightParen: .rightParenToken()
      )
      let throwStmt = ThrowStmtSyntax(
        throwKeyword: .keyword(.throw),
        expression: ExprSyntax(skipCall)
      )

      let wrappedItem = CodeBlockItemSyntax(item: .stmt(StmtSyntax(throwStmt)))
      statementsArray.insert(wrappedItem, at: 0)

      if newFunction.signature.effectSpecifiers?.throwsClause == nil {
        var newSignature = newFunction.signature
        var effects = newSignature.effectSpecifiers ?? FunctionEffectSpecifiersSyntax()

        effects.throwsClause = ThrowsClauseSyntax(
          throwsSpecifier: .keyword(.throws)
        )
        newSignature.effectSpecifiers = effects
        newFunction.signature = newSignature
      }
    }

    newFunction.signature.parameterClause.rightParen.trailingTrivia = []
    newFunction.body?.statements = CodeBlockItemListSyntax(statementsArray.map { $0.trimmed })

    let formattedFunction = newFunction.formatted().as(FunctionDeclSyntax.self)
    return formattedFunction ?? newFunction
  }

  private static func isXCTSkipStatement(_ item: CodeBlockItemSyntax) -> Bool {
    guard let throwStmt = item.item.as(StmtSyntax.self)?.as(ThrowStmtSyntax.self),
      let callExpr = throwStmt.expression.as(FunctionCallExprSyntax.self),
      let declRef = callExpr.calledExpression.as(DeclReferenceExprSyntax.self)
    else {
      return false
    }
    return declRef.baseName.text == "XCTSkip"
  }

  private static func bodyRequiresThrows(_ body: CodeBlockSyntax) -> Bool {
    for item in body.statements {
      if item.item.is(ThrowStmtSyntax.self) {
        return true
      }
      // Plain `try` requires the enclosing function to be declared `throws`.
      // `try?` and `try!` do not.
      if let tryExpr = item.item.as(ExprSyntax.self)?.as(TryExprSyntax.self), tryExpr.questionOrExclamationMark == nil {
        return true
      }
    }
    return false
  }
}
