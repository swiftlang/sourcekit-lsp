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

import SwiftRefactor
import SwiftSyntax

/// Syntactic code action provider to swap the left and right operands of a
/// binary expression, adjusting the operator if needed.
///
/// For commutative operators the operands are simply swapped:
/// ```swift
/// let x = a == b  →  let x = b == a
/// ```
///
/// For comparison operators the operator is also flipped:
/// ```swift
/// if 5 < count { }  →  if count > 5 { }
/// ```
struct FlipBinaryOperands: EditRefactoringProvider {
  /// Operators that are known to be commutative or have a well-defined flip.
  /// We only offer the action for these to avoid flipping user-defined or
  /// non-commutative operators (e.g. `+` on strings, `-`, `/`).
  private static let allowedOperators: Set<String> = [
    "==", "!=", "&&", "||", "&", "|", "^",
    "<", ">", "<=", ">=",
  ]

  static func textRefactor(syntax: InfixOperatorExprSyntax, in context: Void) -> [SourceEdit] {
    guard let binaryOp = syntax.operator.as(BinaryOperatorExprSyntax.self) else {
      return []
    }

    let operatorText = binaryOp.operator.text
    guard allowedOperators.contains(operatorText) else {
      return []
    }

    let flippedOp = flippedOperatorText(for: operatorText)

    // Swap operands: right becomes left and left becomes right.
    // Preserve the leading trivia of the original left on the new left,
    // and the trailing trivia of the original right on the new right.
    let newLeft = syntax.rightOperand
      .with(\.leadingTrivia, syntax.leftOperand.leadingTrivia)
      .with(\.trailingTrivia, syntax.leftOperand.trailingTrivia)
    let newRight = syntax.leftOperand
      .with(\.leadingTrivia, syntax.rightOperand.leadingTrivia)
      .with(\.trailingTrivia, syntax.rightOperand.trailingTrivia)

    // Always construct the (potentially flipped) operator, preserving trivia.
    let newOperator = ExprSyntax(
      binaryOp.with(
        \.operator,
        .binaryOperator(flippedOp)
          .with(\.leadingTrivia, binaryOp.operator.leadingTrivia)
          .with(\.trailingTrivia, binaryOp.operator.trailingTrivia)
      )
    )

    let flippedExpr = syntax
      .with(\.leftOperand, ExprSyntax(newLeft))
      .with(\.operator, newOperator)
      .with(\.rightOperand, ExprSyntax(newRight))

    return [
      SourceEdit(range: syntax.position..<syntax.endPosition, replacement: flippedExpr.description)
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

extension FlipBinaryOperands: SyntaxRefactoringCodeActionProvider {
  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: InfixOperatorExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) }
    )
  }

  static var title: String { "Flip binary operands" }
}
