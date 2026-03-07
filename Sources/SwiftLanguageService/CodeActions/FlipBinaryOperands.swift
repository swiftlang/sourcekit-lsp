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
import SwiftSyntax

/// Syntactic code action provider to swap the left and right operands of a
/// binary expression, adjusting the operator if needed.
///
/// For commutative operators the operands are simply swapped:
/// ```swift
/// let sum = 1 + value  →  let sum = value + 1
/// ```
///
/// For comparison operators the operator is also flipped:
/// ```swift
/// if 5 < count { }  →  if count > 5 { }
/// ```
struct FlipBinaryOperands: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange,
      let infixExpr = node.findEnclosingInfixOperator()
    else {
      return []
    }

    let biOperator = infixExpr.operator
    guard let binaryOp = biOperator.as(BinaryOperatorExprSyntax.self) else {
      return []
    }

    let operatorText = binaryOp.operator.text
    let flippedOperator = flippedOperatorText(for: operatorText)

    // Build the flipped expression preserving trivia.
    let leftOperand = infixExpr.leftOperand
    let rightOperand = infixExpr.rightOperand

    // Swap operands: right becomes left and left becomes right.
    // Preserve the leading trivia of the original left on the new left,
    // and the trailing trivia of the original right on the new right.
    let newLeft = rightOperand
      .with(\.leadingTrivia, leftOperand.leadingTrivia)
      .with(\.trailingTrivia, leftOperand.trailingTrivia)
    let newRight = leftOperand
      .with(\.leadingTrivia, rightOperand.leadingTrivia)
      .with(\.trailingTrivia, rightOperand.trailingTrivia)

    let newOperator: ExprSyntax
    if flippedOperator != operatorText {
      newOperator = ExprSyntax(
        binaryOp.with(\.operator, .binaryOperator(flippedOperator))
      )
    } else {
      newOperator = biOperator
    }

    let flippedExpr = infixExpr
      .with(\.leftOperand, ExprSyntax(newLeft))
      .with(\.operator, newOperator)
      .with(\.rightOperand, ExprSyntax(newRight))

    let edit = TextEdit(
      range: scope.snapshot.range(of: infixExpr),
      newText: flippedExpr.description
    )

    return [
      CodeAction(
        title: "Flip operands of '\(operatorText)'",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  /// Returns the flipped operator for comparison operators, or the same
  /// operator text for commutative operators.
  private static func flippedOperatorText(for op: String) -> String {
    switch op {
    case "<": return ">"
    case ">": return "<"
    case "<=": return ">="
    case ">=": return "<="
    default: return op
    }
  }
}

private extension SyntaxProtocol {
  /// Walk up the tree to find the nearest `InfixOperatorExprSyntax` that
  /// contains the current node.
  func findEnclosingInfixOperator() -> InfixOperatorExprSyntax? {
    var current: Syntax? = Syntax(self)
    while let node = current {
      if let infixExpr = node.as(InfixOperatorExprSyntax.self) {
        return infixExpr
      }
      // Stop at statement / declaration boundaries.
      if node.is(CodeBlockItemSyntax.self) || node.is(MemberBlockItemSyntax.self) {
        return nil
      }
      current = node.parent
    }
    return nil
  }
}
