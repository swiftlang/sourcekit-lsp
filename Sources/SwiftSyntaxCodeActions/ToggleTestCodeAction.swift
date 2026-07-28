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

    if let testAttribute = findTestAttribute(in: function) {
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
    // Route to the appropriate toggling logic based on which test framework is detected.
    if let testAttribute = findTestAttribute(in: function) {
      return try toggleSwiftTestingEdits(testAttribute: testAttribute)
    } else if function.isXCTestFunction {
      return try toggleXCTestEdits(function: function)
    } else {
      throw RefactoringNotApplicableError("Function is not a recognized test")
    }
  }

  private static func findTestAttribute(
    in function: FunctionDeclSyntax
  ) -> AttributeSyntax? {
    for element in function.attributes {
      guard case .attribute(let attr) = element else { continue }

      let name = attr.attributeName.trimmedDescription
      if name == "Test" || name == "Testing.Test" {
        return attr
      }
    }
    return nil
  }

  private static func hasConditionalDisabledTrait(_ testAttribute: AttributeSyntax) -> Bool {
    guard case .argumentList(let arguments) = testAttribute.arguments else {
      return false
    }

    return arguments.contains { argument in
      guard let disabledCall = argument.expression.as(FunctionCallExprSyntax.self) else {
        return false
      }

      return disabledCall.isSwiftTestingConditionalDisabledTrait
    }
  }

  private static func toggleSwiftTestingEdits(testAttribute: AttributeSyntax) throws -> [SourceEdit] {
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
      // The test is currently enabled, so disable it by adding the `.disabled()` trait.
      let disabledExpr = ExprSyntax(
        MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier("disabled")))
      )
      let disabledCall = FunctionCallExprSyntax(
        calledExpression: disabledExpr,
        leftParen: .leftParenToken(),
        arguments: [],
        rightParen: .rightParenToken()
      )

      var newTrait = LabeledExprSyntax(expression: ExprSyntax(disabledCall))

      let insertIndex = argumentsArray.firstIndex(where: { $0.label != nil }) ?? argumentsArray.count

      if insertIndex < argumentsArray.count {
        newTrait.trailingComma = .commaToken(trailingTrivia: .space)
        argumentsArray.insert(newTrait, at: insertIndex)
      } else {
        if !argumentsArray.isEmpty, argumentsArray[argumentsArray.count - 1].trailingComma == nil {
          argumentsArray[argumentsArray.count - 1].trailingComma = .commaToken(trailingTrivia: .space)
        }
        argumentsArray.append(newTrait)
      }

      newAttribute.leftParen = testAttribute.leftParen ?? .leftParenToken()
      newAttribute.arguments = .argumentList(LabeledExprListSyntax(argumentsArray))
      newAttribute.rightParen = testAttribute.rightParen ?? .rightParenToken()
    }

    return [
      SourceEdit(
        range: testAttribute.trimmedRange,
        replacement: newAttribute.trimmedDescription
      )
    ]
  }

  private static func isDisabledTrait(_ expr: ExprSyntax) -> Bool {
    guard let disabledCall = expr.as(FunctionCallExprSyntax.self),
      let memberAccess = disabledCall.calledExpression.as(MemberAccessExprSyntax.self)
    else {
      return false
    }
    return memberAccess.declName.baseName.text == "disabled"
  }

  private static func toggleXCTestEdits(function: FunctionDeclSyntax) throws -> [SourceEdit] {
    guard let body = function.body else {
      throw RefactoringNotApplicableError("XCTest function has no body")
    }

    if let firstStatement = body.statements.first, isXCTSkipStatement(firstStatement) {
      return [
        SourceEdit(
          range: firstStatement.position..<firstStatement.endPosition,
          replacement: ""
        )
      ]
    } else {
      var edits: [SourceEdit] = []
      if function.signature.effectSpecifiers?.throwsClause == nil {
        let position =
          function.signature.effectSpecifiers?.asyncSpecifier?.endPositionBeforeTrailingTrivia
          ?? function.signature.parameterClause.endPositionBeforeTrailingTrivia
        edits.append(
          SourceEdit(
            range: position..<position,
            replacement: " throws"
          )
        )
      }

      if let firstStatement = body.statements.first {
        let insertionPosition = firstStatement.positionAfterSkippingLeadingTrivia
        let statementIndentation = firstStatement.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []

        edits.append(
          SourceEdit(
            range: insertionPosition..<insertionPosition,
            replacement: "throw XCTSkip(\"Disabled\")\n\(statementIndentation.description)"
          )
        )
      } else {
        let insertionPosition = body.rightBrace.positionAfterSkippingLeadingTrivia
        let baseIndentation = body.rightBrace.indentationOfLine
        let indentStep = BasicFormat.inferIndentation(of: Syntax(function.root)) ?? .spaces(4)
        let innerIndentation = baseIndentation + indentStep
        let hasNewline = body.rightBrace.leadingTrivia.contains(where: \.isNewline)
        let replacementText =
          hasNewline
          ? "\(indentStep.description)throw XCTSkip(\"Disabled\")\n\(baseIndentation.description)"
          : "\n\(innerIndentation.description)throw XCTSkip(\"Disabled\")\n\(baseIndentation.description)"

        edits.append(
          SourceEdit(
            range: insertionPosition..<insertionPosition,
            replacement: replacementText
          )
        )
      }

      return edits
    }
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
