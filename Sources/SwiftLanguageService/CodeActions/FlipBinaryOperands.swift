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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftOperators
import SwiftSyntax

/// A code action that flips the operands of a binary expression, adjusting
/// the operator if needed (e.g. `<` becomes `>`).
///
/// Examples:
/// - `5 < count` → `count > 5`
/// - `1 + value` → `value + 1`
/// - `a == b` → `b == a`
struct FlipBinaryOperands: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    // Find the nearest SequenceExprSyntax — this is the unfolded binary expression
    // in the raw syntax tree. After operator folding, it becomes InfixOperatorExprSyntax.
    guard let seqExpr = node.findParentOfSelf(
      ofType: SequenceExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) }
    ) else {
      return []
    }

    // Fold the sequence expression to get structured InfixOperatorExprSyntax.
    guard let folded = OperatorTable.standardOperators.foldAll(
      ExprSyntax(seqExpr),
      errorHandler: { _ in }
    ).as(ExprSyntax.self) else {
      return []
    }

    // Find the innermost InfixOperatorExprSyntax with a flippable operator.
    guard let infixExpr = findInnermostFlippableInfix(in: folded) else {
      return []
    }

    guard let binOp = infixExpr.operator.as(BinaryOperatorExprSyntax.self) else {
      return []
    }

    let opText = binOp.operator.text
    let flippedOp = operatorFlipMap[opText] ?? opText

    // Swap operands, preserving trivia positions.
    let newLeft = infixExpr.rightOperand
      .with(\.leadingTrivia, infixExpr.leftOperand.leadingTrivia)
      .with(\.trailingTrivia, infixExpr.leftOperand.trailingTrivia)
    let newRight = infixExpr.leftOperand
      .with(\.leadingTrivia, infixExpr.rightOperand.leadingTrivia)
      .with(\.trailingTrivia, infixExpr.rightOperand.trailingTrivia)

    let newBinOp = binOp.with(\.operator.tokenKind, .binaryOperator(flippedOp))

    let newExpr = infixExpr
      .with(\.leftOperand, newLeft)
      .with(\.operator, ExprSyntax(newBinOp))
      .with(\.rightOperand, newRight)

    let originalText = infixExpr.trimmedDescription
    let newText = newExpr.trimmedDescription

    // Don't offer the action if nothing would change.
    if originalText == newText {
      return []
    }

    return [
      CodeAction(
        title: "Flip operands of '\(originalText)' to '\(newText)'",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: Range(
                  uncheckedBounds: (
                    lower: scope.snapshot.position(of: seqExpr.positionAfterSkippingLeadingTrivia),
                    upper: scope.snapshot.position(of: seqExpr.endPositionBeforeTrailingTrivia)
                  )
                ),
                newText: newExpr.trimmedDescription
              )
            ]
          ]
        )
      )
    ]
  }

  /// Find the innermost InfixOperatorExprSyntax with a flippable operator.
  private static func findInnermostFlippableInfix(in expr: ExprSyntax) -> InfixOperatorExprSyntax? {
    if let infix = expr.as(InfixOperatorExprSyntax.self),
       let binOp = infix.operator.as(BinaryOperatorExprSyntax.self),
       flippableOperators.contains(binOp.operator.text) {
      // Try to find a deeper infix in left or right operand first.
      if let deeper = findInnermostFlippableInfix(in: infix.leftOperand)
          ?? findInnermostFlippableInfix(in: infix.rightOperand) {
        return deeper
      }
      return infix
    }

    for child in expr.children(viewMode: .sourceAccurate) {
      if let childExpr = child.as(ExprSyntax.self),
         let found = findInnermostFlippableInfix(in: childExpr) {
        return found
      }
    }
    return nil
  }

  /// Operators where flipping operands is meaningful.
  private static let flippableOperators: Set<String> = [
    "<", ">", "<=", ">=",
    "==", "!=", "===", "!==",
    "+", "*",
    "&", "|", "^",
    "&&", "||",
  ]

  /// Maps non-commutative operators to their flipped counterparts.
  /// Commutative operators are absent — they remain unchanged.
  private static let operatorFlipMap: [String: String] = [
    "<": ">",
    ">": "<",
    "<=": ">=",
    ">=": "<=",
  ]
}
