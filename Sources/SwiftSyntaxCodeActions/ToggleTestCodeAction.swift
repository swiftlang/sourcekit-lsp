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

    if let (_, testAttribute) = findTestAttribute(in: function) {
      if hasConditionalDisabledTrait(testAttribute) {
        return nil
      }
      return function
    }

    guard function.isXCTestFunction else {
        return nil
    }

    return function
  }

  package static func textRefactor(syntax function: FunctionDeclSyntax, in context: Void) throws -> [SourceEdit] {
    let refactoredFunction: FunctionDeclSyntax

    // Route to the appropriate toggling logic based on which test framework is detected.
    if let (index, testAttribute) = findTestAttribute(in: function) {
      refactoredFunction = try toggleSwiftTestingTest(
        function: function,
        attributeIndex: index,
        testAttribute: testAttribute
      )
    } else if function.isXCTestFunction {
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

  private static func findTestAttribute(
    in function: FunctionDeclSyntax
  ) -> (index: Int, attribute: AttributeSyntax)? {
    let attributesArray = Array(function.attributes)

    for (index, element) in attributesArray.enumerated() {
      guard case .attribute(let attr) = element else { continue }

      let name = attr.attributeName.trimmedDescription
      if name == "Test" || name == "Testing.Test" {
        return (index: index, attribute: attr)
      }
    }
    return nil
  }

  private static func hasConditionalDisabledTrait(_ testAttribute: AttributeSyntax) -> Bool {
    guard case .argumentList(let arguments) = testAttribute.arguments else {
      return false
    }

    return arguments.contains { argument in
      guard let disabledCall = argument.expression.as(FunctionCallExprSyntax.self),
        let memberAccess = disabledCall.calledExpression.as(MemberAccessExprSyntax.self),
        memberAccess.declName.baseName.text == "disabled"
      else {
        return false
      }

      return disabledCall.arguments.contains { $0.label?.text == "if" }
    }
  }

  private static func toggleSwiftTestingTest(
    function: FunctionDeclSyntax,
    attributeIndex: Int,
    testAttribute: AttributeSyntax
  ) throws -> FunctionDeclSyntax {
    var newAttribute = testAttribute
    var argumentsList = LabeledExprListSyntax([])

    if let arguments = testAttribute.arguments {
      guard case .argumentList(let exprList) = arguments else {
        throw RefactoringNotApplicableError("Unexpected argument type in @Test attribute")
      }
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
      let disabledCall = FunctionCallExprSyntax(
        calledExpression: disabledExpr,
        leftParen: .leftParenToken(),
        arguments: [],
        rightParen: .rightParenToken()
      )

      if !argumentsArray.isEmpty, argumentsArray[argumentsArray.count - 1].trailingComma == nil {
        argumentsArray[argumentsArray.count - 1].trailingComma = .commaToken(trailingTrivia: .space)
      }

      argumentsArray.append(LabeledExprSyntax(expression: ExprSyntax(disabledCall)))

      newAttribute.leftParen = testAttribute.leftParen ?? .leftParenToken()
      newAttribute.arguments = .argumentList(LabeledExprListSyntax(argumentsArray))
      newAttribute.rightParen = testAttribute.rightParen ?? .rightParenToken()
    }

    var attributesArray = Array(function.attributes)
    attributesArray[attributeIndex] = .attribute(newAttribute)

    var newFunction = function
    newFunction.attributes = AttributeListSyntax(attributesArray)

    return newFunction
  }

  private static func isDisabledTrait(_ expr: ExprSyntax) -> Bool {
    guard let disabledCall = expr.as(FunctionCallExprSyntax.self),
      let memberAccess = disabledCall.calledExpression.as(MemberAccessExprSyntax.self)
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

    guard function.signature.parameterClause.parameters.isEmpty else {
      return false
    }

    guard function.signature.returnClause == nil else {
      return false
    }

    guard !function.modifiers.contains(where: {
      let kind = $0.name.tokenKind
      return kind == .keyword(.static) || kind == .keyword(.class)
    }) else {
      return false
    }

    return true
  }

  private static func toggleXCTest(function: FunctionDeclSyntax) -> FunctionDeclSyntax {
    guard let body = function.body else { return function }
    var newFunction = function
    var statementsArray = Array(body.statements)

    if let firstStatement = statementsArray.first, isXCTSkipStatement(firstStatement) {
      statementsArray.removeFirst()
    } else {
      let skipString = StringLiteralExprSyntax(content: "Disabled")
      let skipCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("XCTSkip")),
        leftParen: .leftParenToken(),
        arguments: [LabeledExprSyntax(expression: ExprSyntax(skipString))],
        rightParen: .rightParenToken()
      )
      let throwStmt = ThrowStmtSyntax(
        throwKeyword: .keyword(.throw, trailingTrivia: .space),
        expression: ExprSyntax(skipCall)
      )

      var wrappedItem = CodeBlockItemSyntax(item: .stmt(StmtSyntax(throwStmt)))
      if let firstStmt = statementsArray.first {
        wrappedItem.leadingTrivia = firstStmt.leadingTrivia
      }
      statementsArray.insert(wrappedItem, at: 0)

      if newFunction.signature.effectSpecifiers?.throwsClause == nil {
        var newSignature = newFunction.signature
        var effects = newSignature.effectSpecifiers ?? FunctionEffectSpecifiersSyntax()

        effects.throwsClause = ThrowsClauseSyntax(
          throwsSpecifier: .keyword(.throws, trailingTrivia: .space)
        )
        newSignature.effectSpecifiers = effects
        newFunction.signature = newSignature
      }
    }

    newFunction.body?.statements = CodeBlockItemListSyntax(statementsArray)

    return newFunction
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
}
