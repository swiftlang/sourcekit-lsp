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

/// A code action that reverses a range expression.
///
/// Examples:
/// - `1...10` → `(1...10).reversed()`
/// - `stride(from: 0, to: 10, by: 1)` → `stride(from: 10, to: 0, by: -1)`
struct FlipRangeExpression: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    // Try stride expression first.
    if let result = tryFlipStride(node: node, scope: scope) {
      return result
    }

    // Try range operator expression (1...10 or 1..<10).
    if let result = tryFlipRange(node: node, scope: scope) {
      return result
    }

    return []
  }

  // MARK: - Stride

  private static func tryFlipStride(
    node: Syntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction]? {
    // Find a FunctionCallExprSyntax for `stride(from:to:by:)`.
    guard let callExpr = node.findParentOfSelf(
      ofType: FunctionCallExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) }
    ) else {
      return nil
    }

    guard let calledExpr = callExpr.calledExpression.as(DeclReferenceExprSyntax.self),
          calledExpr.baseName.text == "stride"
    else {
      return nil
    }

    let args = callExpr.arguments
    guard args.count == 3 else { return nil }

    let argList = Array(args)
    guard argList[0].label?.text == "from",
          argList[1].label?.text == "to",
          argList[2].label?.text == "by"
    else {
      return nil
    }

    let fromExpr = argList[0].expression
    let toExpr = argList[1].expression
    let byExpr = argList[2].expression

    // Build the flipped stride: swap from/to, negate by.
    let newFrom = argList[0].with(\.expression, toExpr.with(\.leadingTrivia, fromExpr.leadingTrivia)
                                                        .with(\.trailingTrivia, fromExpr.trailingTrivia))
    let newTo = argList[1].with(\.expression, fromExpr.with(\.leadingTrivia, toExpr.leadingTrivia)
                                                       .with(\.trailingTrivia, toExpr.trailingTrivia))
    let newBy = argList[2].with(\.expression, negateExpression(byExpr))

    let newArgList = LabeledExprListSyntax([newFrom, newTo, newBy])
    let newCall = callExpr.with(\.arguments, newArgList)

    let originalText = callExpr.trimmedDescription
    let newText = newCall.trimmedDescription

    if originalText == newText {
      return nil
    }

    return [
      CodeAction(
        title: "Flip range to '\(newText)'",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: Range(
                  uncheckedBounds: (
                    lower: scope.snapshot.position(of: callExpr.positionAfterSkippingLeadingTrivia),
                    upper: scope.snapshot.position(of: callExpr.endPositionBeforeTrailingTrivia)
                  )
                ),
                newText: newText
              )
            ]
          ]
        )
      )
    ]
  }

  // MARK: - Range operator

  private static func tryFlipRange(
    node: Syntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction]? {
    // Look for a SequenceExprSyntax or InfixOperatorExprSyntax containing a range operator.
    guard let seqExpr = node.findParentOfSelf(
      ofType: SequenceExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) }
    ) else {
      return nil
    }

    let elements = Array(seqExpr.elements)
    guard elements.count == 3,
          let binOp = elements[1].as(BinaryOperatorExprSyntax.self),
          rangeOperators.contains(binOp.operator.text)
    else {
      return nil
    }

    // Wrap in `.reversed()`.
    let originalText = seqExpr.trimmedDescription
    let newText = "(\(originalText)).reversed()"

    return [
      CodeAction(
        title: "Flip range to '(\(originalText)).reversed()'",
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
                newText: newText
              )
            ]
          ]
        )
      )
    ]
  }

  // MARK: - Helpers

  private static let rangeOperators: Set<String> = ["...", "..<"]

  /// Negate a numeric expression. Handles integer/float literals and prefix `-`.
  private static func negateExpression(_ expr: ExprSyntax) -> ExprSyntax {
    // If already negated (prefix `-`), remove the negation.
    if let prefixExpr = expr.as(PrefixOperatorExprSyntax.self),
       prefixExpr.operator.text == "-" {
      return prefixExpr.expression
        .with(\.leadingTrivia, expr.leadingTrivia)
        .with(\.trailingTrivia, expr.trailingTrivia)
    }

    // For integer literals, prepend `-`.
    if let intLiteral = expr.as(IntegerLiteralExprSyntax.self) {
      let negated = PrefixOperatorExprSyntax(
        operator: .prefixOperator("-"),
        expression: ExprSyntax(intLiteral.with(\.leadingTrivia, []))
      )
      return ExprSyntax(negated)
        .with(\.leadingTrivia, expr.leadingTrivia)
        .with(\.trailingTrivia, expr.trailingTrivia)
    }

    // For float literals, prepend `-`.
    if let floatLiteral = expr.as(FloatLiteralExprSyntax.self) {
      let negated = PrefixOperatorExprSyntax(
        operator: .prefixOperator("-"),
        expression: ExprSyntax(floatLiteral.with(\.leadingTrivia, []))
      )
      return ExprSyntax(negated)
        .with(\.leadingTrivia, expr.leadingTrivia)
        .with(\.trailingTrivia, expr.trailingTrivia)
    }

    // General case: wrap in parenthesized negation.
    let negated = PrefixOperatorExprSyntax(
      operator: .prefixOperator("-"),
      expression: ExprSyntax(
        TupleExprSyntax(
          elements: LabeledExprListSyntax([
            LabeledExprSyntax(expression: expr.with(\.leadingTrivia, []).with(\.trailingTrivia, []))
          ])
        )
      )
    )
    return ExprSyntax(negated)
      .with(\.leadingTrivia, expr.leadingTrivia)
      .with(\.trailingTrivia, expr.trailingTrivia)
  }
}
