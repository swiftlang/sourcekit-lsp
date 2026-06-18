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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftOperators
import SwiftSyntax

struct SwapBinaryOperands: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    // Locate the smallest expression that may contain the operator under the cursor.
    // SequenceExprSyntax needs to be folded before precedence-aware rewriting can occur.
    guard
      let exprToFold = node.findParentOfSelf(
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

    // Track both absolute and expression-relative cursor positions.
    // The folded tree produced by SwiftOperators is detached from the
    // original source tree, so operator locations may be relative to
    // the folded expression instead of the source file.
    let absoluteRange = OffsetRange(
      lowerBound: scope.snapshot.absolutePosition(of: scope.request.range.lowerBound).utf8Offset,
      upperBound: scope.snapshot.absolutePosition(of: scope.request.range.upperBound).utf8Offset
    )
    let relativeRange = absoluteRange.offset(by: -exprToFold.position.utf8Offset)

    // Find the specific infix operator whose token range contains
    // the cursor. The code action should only be offered when the
    // cursor is positioned on the operator itself.
    let finder = CursorInfixFinder(cursorRanges: [absoluteRange, relativeRange])
    finder.walk(foldedExpr)

    guard let infixExpr = finder.found else {
      return []
    }

    let opExpr = infixExpr.operator
    let currentOperatorText: String
    if let declRef = opExpr.as(DeclReferenceExprSyntax.self) {
      currentOperatorText = declRef.baseName.text
    } else if let binOp = opExpr.as(BinaryOperatorExprSyntax.self) {
      currentOperatorText = binOp.operator.text
    } else {
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

    // Ignore incomplete expressions produced while the user is typing.
    guard !leftOperand.is(MissingExprSyntax.self), !rightOperand.is(MissingExprSyntax.self) else {
      return []
    }

    // Preserve operand trivia so whitespace and comments remain attached
    // to the same side of the expression after swapping.
    var newLeft = rightOperand
    newLeft.leadingTrivia = leftOperand.leadingTrivia
    newLeft.trailingTrivia = leftOperand.trailingTrivia

    var newRight = leftOperand
    newRight.leadingTrivia = rightOperand.leadingTrivia
    newRight.trailingTrivia = rightOperand.trailingTrivia

    let newOperatorExpr: ExprSyntax
    if let declRef = opExpr.as(DeclReferenceExprSyntax.self) {
      let newToken = declRef.baseName.with(\.tokenKind, .binaryOperator(newOperatorText))
      newOperatorExpr = ExprSyntax(declRef.with(\.baseName, newToken))
    } else if let binOp = opExpr.as(BinaryOperatorExprSyntax.self) {
      let newToken = binOp.operator.with(\.tokenKind, .binaryOperator(newOperatorText))
      newOperatorExpr = ExprSyntax(binOp.with(\.operator, newToken))
    } else {
      return []
    }

    let newInfix =
      infixExpr
      .with(\.leftOperand, newLeft)
      .with(\.operator, newOperatorExpr)
      .with(\.rightOperand, newRight)

    // Replace only the selected infix expression while leaving the
    // surrounding folded expression tree unchanged.
    let finalExpr = SwapRewriter(targetId: infixExpr.id, replacement: newInfix).visit(foldedExpr)

    return [
      CodeAction(
        title: "Swap operands",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: scope.snapshot.range(of: exprToFold),
                newText: finalExpr.description
              )
            ]
          ]
        )
      )
    ]
  }
}

/// UTF-8 offset range used for comparing cursor positions against
/// operator token ranges without relying on source locations.
private struct OffsetRange {
  let lowerBound: Int
  let upperBound: Int

  init(_ range: Range<AbsolutePosition>) {
    self.lowerBound = range.lowerBound.utf8Offset
    self.upperBound = range.upperBound.utf8Offset
  }

  init(lowerBound: Int, upperBound: Int) {
    self.lowerBound = lowerBound
    self.upperBound = upperBound
  }

  func offset(by amount: Int) -> OffsetRange {
    OffsetRange(lowerBound: lowerBound + amount, upperBound: upperBound + amount)
  }

  func contains(_ other: OffsetRange) -> Bool {
    if other.lowerBound == other.upperBound {
      return lowerBound <= other.lowerBound && other.lowerBound < upperBound
    }
    return lowerBound <= other.lowerBound && other.upperBound <= upperBound
  }
}

private extension TokenSyntax {
  var tokenTextOffsetRange: OffsetRange {
    OffsetRange(
      lowerBound: positionAfterSkippingLeadingTrivia.utf8Offset,
      upperBound: endPositionBeforeTrailingTrivia.utf8Offset
    )
  }
}

private extension ExprSyntax {
  var operatorTokenTextOffsetRange: OffsetRange? {
    if let declRef = self.as(DeclReferenceExprSyntax.self) {
      return declRef.baseName.tokenTextOffsetRange
    }
    if let binOp = self.as(BinaryOperatorExprSyntax.self) {
      return binOp.operator.tokenTextOffsetRange
    }
    return nil
  }
}

/// Finds the innermost infix operator whose token range contains
/// the cursor position.
private final class CursorInfixFinder: SyntaxVisitor {
  var found: InfixOperatorExprSyntax?
  let cursorRanges: [OffsetRange]

  init(cursorRanges: [OffsetRange]) {
    self.cursorRanges = cursorRanges
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
    guard let operatorRange = node.operator.operatorTokenTextOffsetRange else {
      return .visitChildren
    }

    if cursorRanges.contains(where: { operatorRange.contains($0) }) {
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
