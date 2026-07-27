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
    // Route to the appropriate toggling logic based on which test framework is detected.
    if let (_, testAttribute) = findTestAttribute(in: function) {
      let newAttribute = try toggleSwiftTestingTest(testAttribute: testAttribute)
      return [
        SourceEdit(
          range: testAttributeRange(testAttribute),
          replacement: newAttribute.trimmedDescription
        )
      ]
    } else if function.isXCTestFunction {
      return try toggleXCTestEdits(function: function)
    } else {
      throw RefactoringNotApplicableError("Function is not a recognized test")
    }
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

  private static func testAttributeRange(_ testAttribute: AttributeSyntax) -> Range<AbsolutePosition> {
    let range = testAttribute.trimmedRange
    if !range.isEmpty {
      return range
    }
    return testAttribute.positionAfterSkippingLeadingTrivia..<testAttribute.endPositionBeforeTrailingTrivia
  }

  private static func toggleSwiftTestingTest(testAttribute: AttributeSyntax) throws -> AttributeSyntax {
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

    return newAttribute
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

    guard
      !function.modifiers.contains(where: {
        let kind = $0.name.tokenKind
        return kind == .keyword(.static) || kind == .keyword(.class)
      })
    else {
      return false
    }

    return true
  }

  private static func toggleXCTestEdits(function: FunctionDeclSyntax) throws -> [SourceEdit] {
    guard let body = function.body else {
      throw RefactoringNotApplicableError("XCTest function has no body")
    }

    if let firstStatement = body.statements.first, isXCTSkipStatement(firstStatement) {
      return [
        SourceEdit(
          range: firstStatement.positionAfterSkippingLeadingTrivia..<firstStatement.endPositionBeforeTrailingTrivia,
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

      let insertionPosition: AbsolutePosition
      let indentation: String

      if let firstStatement = body.statements.first {
        insertionPosition = firstStatement.positionAfterSkippingLeadingTrivia
        indentation = indentationBefore(firstStatement)

        edits.append(
          SourceEdit(
            range: insertionPosition..<insertionPosition,
            replacement: "throw XCTSkip(\"Disabled\")\n\(indentation)"
          )
        )
      } else {
        insertionPosition = body.rightBrace.positionAfterSkippingLeadingTrivia

        let hasNewline = body.rightBrace.leadingTrivia.description.contains("\n")

        let baseIndentation = indentationBefore(function)
        let innerIndentation = baseIndentation + "    "

        let replacementText: String
        if hasNewline {
          replacementText = "    throw XCTSkip(\"Disabled\")\n\(baseIndentation)"
        } else {
          replacementText = "\n\(innerIndentation)throw XCTSkip(\"Disabled\")\n\(baseIndentation)"
        }

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

  private static func indentationBefore(_ node: some SyntaxProtocol) -> String {
    let leadingTrivia = node.leadingTrivia.description
    guard let lastNewline = leadingTrivia.lastIndex(of: "\n") else {
      return leadingTrivia
    }
    return String(leadingTrivia[leadingTrivia.index(after: lastNewline)...])
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
