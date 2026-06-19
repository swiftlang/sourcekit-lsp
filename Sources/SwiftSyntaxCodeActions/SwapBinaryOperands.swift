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
      opExpr.findParentOfSelf(
        ofType: ExprSyntax.self,
        stoppingIf: { $0.is(CodeBlockItemSyntax.self) },
        matching: { $0.is(SequenceExprSyntax.self) || $0.is(InfixOperatorExprSyntax.self) }
      ) != nil
    else {
      return nil
    }

    let token = opExpr.operator
    let tokenStart = token.positionAfterSkippingLeadingTrivia
    let tokenEnd = token.endPositionBeforeTrailingTrivia

    let startPos = scope.snapshot.absolutePosition(of: scope.request.range.lowerBound)
    let endPos = scope.snapshot.absolutePosition(of: scope.request.range.upperBound)

    // Restrict the action to selections that fall within the operator token
    // itself. This prevents offering the action when the cursor is placed on
    // either operand or in surrounding trivia.
    guard startPos >= tokenStart else { return nil }
    if startPos == endPos {
      guard startPos < tokenEnd else { return nil }
    } else {
      guard endPos <= tokenEnd else { return nil }
    }

    return ExprSyntax(opExpr)
  }

  package static func textRefactor(syntax opExpr: ExprSyntax, in context: Void) throws -> [SourceEdit] {
    guard let binOp = opExpr.as(BinaryOperatorExprSyntax.self) else {
      return []
    }

    // Locate the smallest expression that may contain the operator under the cursor.
    // SequenceExprSyntax needs to be folded before precedence-aware rewriting can occur.
    guard
      let exprToFold = binOp.findParentOfSelf(
        ofType: ExprSyntax.self,
        stoppingIf: { $0.is(CodeBlockItemSyntax.self) },
        matching: { $0.is(SequenceExprSyntax.self) || $0.is(InfixOperatorExprSyntax.self) }
      )
    else {
      return []
    }

    let foldedExpr: ExprSyntax

    // Fold operator precedence so nested expressions such as
    // `1 + -2 * 5` become a structured tree where the selected
    // infix operator can be identified reliably.
    if exprToFold.is(SequenceExprSyntax.self) {
      guard let folded = OperatorTable.standardOperators.foldAll(exprToFold, errorHandler: { _ in }).as(ExprSyntax.self)
      else {
        return []
      }
      foldedExpr = folded
    } else {
      foldedExpr = exprToFold.detached
    }

    let currentOperatorText = binOp.operator.text

    // Calculate the relative UTF-8 offset.
    let targetRelativeOffset =
      binOp.operator.positionAfterSkippingLeadingTrivia.utf8Offset - exprToFold.position.utf8Offset

    let finder = OperatorMatchFinder(
      targetText: currentOperatorText,
      targetRelativeOffset: targetRelativeOffset,
      rootPosition: foldedExpr.position
    )
    finder.walk(foldedExpr)

    guard let infixExpr = finder.found else {
      return []
    }

    // Avoid offering the refactoring for malformed expressions such as
    // `a +` or `+ b` while the user is still typing.
    guard !infixExpr.hasError else {
      return []
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
      return []
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
      return []
    }
    let newToken = targetBinOp.operator.with(\.tokenKind, .binaryOperator(newOperatorText))
    let newOperatorExpr = ExprSyntax(targetBinOp.with(\.operator, newToken))

    let newInfix =
      infixExpr
      .with(\.leftOperand, newLeft)
      .with(\.operator, newOperatorExpr)
      .with(\.rightOperand, newRight)

    // Replace only the selected infix expression while leaving the
    // surrounding folded expression tree unchanged.
    let finalExpr = SwapRewriter(targetId: infixExpr.id, replacement: newInfix).visit(foldedExpr)

    return [
      SourceEdit(
        range: exprToFold.position..<exprToFold.endPosition,
        replacement: finalExpr.description
      )
    ]
  }
}

/// Finds the InfixOperatorExprSyntax in the folded tree that corresponds
/// to the operator selected in the original source expression.
private final class OperatorMatchFinder: SyntaxVisitor {
  var found: InfixOperatorExprSyntax?
  let targetText: String
  let targetRelativeOffset: Int
  let rootPosition: AbsolutePosition

  init(targetText: String, targetRelativeOffset: Int, rootPosition: AbsolutePosition) {
    self.targetText = targetText
    self.targetRelativeOffset = targetRelativeOffset
    self.rootPosition = rootPosition
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
    guard let binOp = node.operator.as(BinaryOperatorExprSyntax.self) else {
      return .visitChildren
    }

    let currentText = binOp.operator.text
    let currentPosition = binOp.operator.positionAfterSkippingLeadingTrivia

    let relativeOffset = currentPosition.utf8Offset - rootPosition.utf8Offset
    if currentText == targetText && relativeOffset == targetRelativeOffset {
      self.found = node
      return .skipChildren
    }
    return .visitChildren
  }
}

/// Replaces a single infix expression identified by SyntaxIdentifier.
private class SwapRewriter: SyntaxRewriter {
  let targetId: SyntaxIdentifier
  let newInfix: InfixOperatorExprSyntax

  init(targetId: SyntaxIdentifier, replacement: InfixOperatorExprSyntax) {
    self.targetId = targetId
    self.newInfix = replacement
  }

  override func visit(_ node: InfixOperatorExprSyntax) -> ExprSyntax {
    if node.id == targetId {
      return ExprSyntax(newInfix)
    }
    return super.visit(node)
  }
}
