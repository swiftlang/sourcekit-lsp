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
import SwiftExtensions
import SwiftOperators
import SwiftRefactor
import SwiftSyntax

struct SwapBinaryOperands: SyntaxRefactoringCodeActionProvider {
  package static let title: String = "Swap operands"

  package static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> ExprSyntax? {
    guard let node = scope.innermostNodeContainingRange else {
      return nil
    }

    guard
      let opExpr = node.findParentOfSelf(
        ofType: ExprSyntax.self,
        stoppingIf: { $0.is(CodeBlockItemSyntax.self) },
        matching: { $0.is(BinaryOperatorExprSyntax.self) }
      )?.as(BinaryOperatorExprSyntax.self)
    else {
      return nil
    }

    // Only offer the refactoring when the operator participates in a
    // binary expression that can be folded into an InfixOperatorExprSyntax.
    guard
      opExpr.parent?.is(InfixOperatorExprSyntax.self) == true
        || opExpr.parent?.as(ExprListSyntax.self)?.parent?.is(SequenceExprSyntax.self) == true
    else {
      return nil
    }

    let startPos = scope.snapshot.absolutePosition(of: scope.request.range.lowerBound)
    let endPos = scope.snapshot.absolutePosition(of: scope.request.range.upperBound)
    let selectionRange = startPos..<endPos

    // Only offer the refactoring when the cursor or selection targets the
    // operator token. This prevents offering the action when the cursor is placed on
    // either operand or in surrounding trivia.
    let tokenRange = opExpr.operator.trimmedRange
    guard selectionRange.overlapsOrTouches(tokenRange) else {
      return nil
    }

    return ExprSyntax(opExpr)
  }

  package static func textRefactor(syntax opExpr: ExprSyntax, in context: Void) throws -> [SourceEdit] {
    guard let binOp = opExpr.as(BinaryOperatorExprSyntax.self) else {
      throw RefactoringNotApplicableError("Selected expression is not a binary operator")
    }

    // Locate the smallest expression that may contain the operator under the cursor.
    // SequenceExprSyntax needs to be folded before precedence-aware rewriting can occur.
    let exprToFold: ExprSyntax
    if let infixExpr = binOp.parent?.as(InfixOperatorExprSyntax.self) {
      exprToFold = ExprSyntax(infixExpr)
    } else if let seqExpr = binOp.parent?.as(ExprListSyntax.self)?.parent?.as(SequenceExprSyntax.self) {
      exprToFold = ExprSyntax(seqExpr)
    } else {
      throw RefactoringNotApplicableError("Could not find an infix or sequence expression to fold")
    }

    let foldedExpr: ExprSyntax

    // Fold operator precedence so nested expressions such as
    // `1 + -2 * 5` become a structured tree where the selected
    // infix operator can be identified reliably.
    if exprToFold.is(SequenceExprSyntax.self) {
      guard let folded = OperatorTable.standardOperators.foldAll(exprToFold, errorHandler: { _ in }).as(ExprSyntax.self)
      else {
        throw RefactoringNotApplicableError("Failed to fold operator sequence")
      }
      foldedExpr = folded
    } else {
      foldedExpr = exprToFold.detached
    }

    let currentOperatorText = binOp.operator.text

    // Calculate the relative UTF-8 offset.
    let targetRelativeOffset =
      binOp.operator.positionAfterSkippingLeadingTrivia.utf8Offset - exprToFold.position.utf8Offset
    let targetPosition = AbsolutePosition(utf8Offset: foldedExpr.position.utf8Offset + targetRelativeOffset)

    guard
      let token = foldedExpr.token(at: targetPosition),
      let infixExpr = token.parent?.as(BinaryOperatorExprSyntax.self)?.parent?.as(InfixOperatorExprSyntax.self)
    else {
      throw RefactoringNotApplicableError("Could not locate the target operator in the folded tree")
    }

    // Avoid offering the refactoring for malformed expressions such as
    // `a +` or `+ b` while the user is still typing.
    guard !infixExpr.hasError else {
      throw RefactoringNotApplicableError("Expression is malformed or incomplete")
    }

    let newOperatorText: String

    // Comparison operators must be inverted when operands are swapped.
    // Symmetric operators can be reused unchanged.
    switch currentOperatorText {
    case "<": newOperatorText = ">"
    case ">": newOperatorText = "<"
    case "<=": newOperatorText = ">="
    case ">=": newOperatorText = "<="
    case "+", "*", "==", "!=", "===", "!==", "&&", "||", "&", "|", "^":
      newOperatorText = currentOperatorText
    default:
      throw RefactoringNotApplicableError("Operator '\(currentOperatorText)' cannot be swapped")
    }

    let leftOperand = infixExpr.leftOperand
    let rightOperand = infixExpr.rightOperand

    // Preserve operand trivia so whitespace and comments remain attached
    // to the same side of the expression after swapping.
    var newLeft = rightOperand
    newLeft.leadingTrivia = leftOperand.leadingTrivia
    newLeft.trailingTrivia = leftOperand.trailingTrivia

    var newRight = leftOperand
    newRight.leadingTrivia = rightOperand.leadingTrivia
    newRight.trailingTrivia = rightOperand.trailingTrivia

    guard let targetBinOp = infixExpr.operator.as(BinaryOperatorExprSyntax.self) else {
      throw RefactoringNotApplicableError("Failed to cast operator to BinaryOperatorExprSyntax")
    }
    let newToken = targetBinOp.operator.with(\.tokenKind, .binaryOperator(newOperatorText))
    let newOperatorExpr = ExprSyntax(targetBinOp.with(\.operator, newToken))

    let newInfix =
      infixExpr
      .with(\.leftOperand, newLeft)
      .with(\.operator, newOperatorExpr)
      .with(\.rightOperand, newRight)

    // Calculate the absolute range of the targeted expression in the original source
    // by applying its relative offset from the detached folded tree.
    let rootOffset = exprToFold.position.utf8Offset
    let foldedRootOffset = foldedExpr.position.utf8Offset

    let startOffset = rootOffset + (infixExpr.position.utf8Offset - foldedRootOffset)
    let endOffset = rootOffset + (infixExpr.endPosition.utf8Offset - foldedRootOffset)

    let editRange = AbsolutePosition(utf8Offset: startOffset)..<AbsolutePosition(utf8Offset: endOffset)

    return [
      SourceEdit(
        range: editRange,
        replacement: newInfix.description
      )
    ]
  }
}
