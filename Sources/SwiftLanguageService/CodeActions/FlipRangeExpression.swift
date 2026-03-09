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
import SwiftExtensions
import SwiftSyntax

/// A code action that flips range expressions: reverses the bounds of a stride
/// or wraps a range in `.reversed()`.
///
/// - `stride(from: 0, to: 10, by: 1)` → `stride(from: 10, to: 0, by: -1)`
/// - `1...10` → `(1...10).reversed()`
/// - `1..<10` → `(1..<10).reversed()`
///
/// Implemented as `SyntaxCodeActionProvider` (not `SyntaxRefactoringCodeActionProvider`)
/// because there is no corresponding refactoring in SwiftRefactor; adding one would require
/// a new refactoring in the swift-syntax package.
struct FlipRangeExpression: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    // Use the token at the start of the range so we find the expression that contains
    // the selection even when the range end is exactly at the expression boundary
    // (otherwise the right token can be the next token and the common ancestor is too high).
    if let startToken = scope.file.token(at: scope.range.lowerBound) {
      let node = Syntax(startToken)
      if let action = flipStride(scope: scope, from: node) {
        return [action]
      }
      if let action = flipRangeOperator(scope: scope, from: node) {
        return [action]
      }
    }
    // Fallback: selection may have made the common ancestor the range or a tuple containing it.
    if let inner = scope.innermostNodeContainingRange,
      let action = flipRangeOperator(scope: scope, from: inner)
    {
      return [action]
    }
    return []
  }
}

// MARK: - Stride

private func flipStride(scope: SyntaxCodeActionScope, from node: Syntax) -> CodeAction? {
  guard let call = node.findParentOfSelf(
    ofType: FunctionCallExprSyntax.self,
    stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
  ) else {
    return nil
  }

  guard isStrideCall(call),
    let fromArg = findArgument(label: "from", in: call.arguments),
    let toArg = findArgument(label: "to", in: call.arguments),
    let byArg = findArgument(label: "by", in: call.arguments)
  else {
    return nil
  }

  let fromText = fromArg.expression.description
  let toText = toArg.expression.description
  let negatedByText = negateStrideStepText(byArg.expression)
  let newText = "stride(from: \(toText), to: \(fromText), by: \(negatedByText))"

  let range = scope.snapshot.range(of: call)
  return CodeAction(
    title: "Flip range expression",
    kind: .refactorInline,
    edit: WorkspaceEdit(
      changes: [
        scope.snapshot.uri: [
          TextEdit(range: range, newText: newText)
        ]
      ]
    )
  )
}

private func isStrideCall(_ call: FunctionCallExprSyntax) -> Bool {
  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "stride"
}

private func findArgument(label: String, in arguments: LabeledExprListSyntax) -> LabeledExprSyntax? {
  arguments.first { $0.label?.text == label }
}

/// Returns the source text for the negated stride step. Toggles a leading "-" when present
/// so that applying the action twice restores the original (e.g. "1" → "-1", "-1" → "1").
/// For other expressions, prepends "-" (with parens if needed for precedence).
private func negateStrideStepText(_ expr: ExprSyntax) -> String {
  let inner = expr.lookingThroughParentheses
  let text = inner.description

  // Add "-" if there isn't one, remove it if there is (no Int/float conversion).
  if text.hasPrefix("-") {
    return String(text.dropFirst(1).drop(while: { $0.isWhitespace }))
  }
  let exprText = expr.description
  if expr.needParensForPrefixMinus {
    return "-(\(exprText))"
  }
  return "-\(exprText)"
}

private extension ExprSyntax {
  var lookingThroughParentheses: ExprSyntax {
    if let tuple = self.as(TupleExprSyntax.self), let single = tuple.singleElementExpression {
      return single.lookingThroughParentheses
    }
    return self
  }

  /// True if the expression needs parentheses when wrapped in a prefix "-" to preserve meaning.
  /// Uses a whitelist of expression kinds that are safe without parens; errs on the side of adding parens.
  var needParensForPrefixMinus: Bool {
    switch self.kind {
    case .integerLiteralExpr, .floatLiteralExpr, .booleanLiteralExpr, .nilLiteralExpr,
      .stringLiteralExpr, .regexLiteralExpr, .declReferenceExpr, .memberAccessExpr,
      .functionCallExpr, .subscriptCallExpr, .optionalChainingExpr, .arrayExpr,
      .dictionaryExpr, .tupleExpr, .keyPathExpr, .macroExpansionExpr, .superExpr:
      return false
    default:
      return true
    }
  }
}

private extension TupleExprSyntax {
  var singleElementExpression: ExprSyntax? {
    guard let only = elements.only, only.label == nil else { return nil }
    return only.expression
  }
}

// MARK: - Range operator

/// Range expressions like `1..<10` or `1...10` can appear as either
/// `InfixOperatorExprSyntax` (after operator folding) or `SequenceExprSyntax`
/// with three elements [left, BinaryOperatorExpr(..< or ...), right].
/// We support both so the action works without running SwiftOperators (e.g. in single-file or
/// no-workspace cases). Running SwiftOperators could fold to InfixOperatorExpr and allow
/// simplifying to a single path.
private func flipRangeOperator(scope: SyntaxCodeActionScope, from node: Syntax) -> CodeAction? {
  // Node may be the range expression itself (e.g. from innermostNodeContainingRange) or a token inside it.
  if let infix = node.as(InfixOperatorExprSyntax.self)
    ?? node.findParentOfSelf(
      ofType: InfixOperatorExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  {
    if let binOp = infix.operator.as(BinaryOperatorExprSyntax.self),
      binOp.operator.text == "..." || binOp.operator.text == "..<"
    {
      if let action = unflipRangeIfReversed(scope: scope, rangeNode: Syntax(infix)) {
        return action
      }
      return makeFlipRangeCodeAction(scope: scope, rangeNode: Syntax(infix))
    }
  }
  if let seq = node.as(SequenceExprSyntax.self)
    ?? node.findParentOfSelf(
      ofType: SequenceExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  {
    let elements = seq.elements
    if elements.count == 3,
      let middleExpr = elements.dropFirst(1).first,
      let binOp = middleExpr.as(BinaryOperatorExprSyntax.self),
      binOp.operator.text == "..." || binOp.operator.text == "..<"
    {
      if let action = unflipRangeIfReversed(scope: scope, rangeNode: Syntax(seq)) {
        return action
      }
      return makeFlipRangeCodeAction(scope: scope, rangeNode: Syntax(seq))
    }
  }
  // Tuple with single element (e.g. (1..<10)): try the element's expression as the range.
  if let tuple = node.as(TupleExprSyntax.self), let inner = tuple.singleElementExpression {
    return flipRangeOperator(scope: scope, from: Syntax(inner))
  }
  return nil
}

/// If `rangeNode` is the inner expression of `(rangeNode).reversed()`, returns a code action
/// that replaces the whole call with just the range (so applying the action twice restores the original).
private func unflipRangeIfReversed(scope: SyntaxCodeActionScope, rangeNode: Syntax) -> CodeAction? {
  // Find .reversed() by walking up from the range; then confirm its base is a single-element tuple containing our range.
  guard let memberAccess = rangeNode.findParentOfSelf(
    ofType: MemberAccessExprSyntax.self,
    stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
  ),
    memberAccess.declName.baseName.text == "reversed",
    let tuple = memberAccess.base?.as(TupleExprSyntax.self),
    let singleElement = tuple.elements.only
  else {
    return nil
  }
  // Tuple element is the range; strip any single-element tuple wrapping (e.g. (1..<10) in some parses).
  guard singleElement.expression.lookingThroughParentheses.description == rangeNode.description else {
    return nil
  }
  // Replace the full .reversed() call (including parentheses) when it has no arguments.
  let nodeToReplace: Syntax =
    (memberAccess.parent?.as(FunctionCallExprSyntax.self)).map { call in
      call.arguments.isEmpty ? Syntax(call) : Syntax(memberAccess)
    } ?? Syntax(memberAccess)
  let range = scope.snapshot.range(of: nodeToReplace)
  return CodeAction(
    title: "Flip range expression",
    kind: .refactorInline,
    edit: WorkspaceEdit(
      changes: [
        scope.snapshot.uri: [
          TextEdit(range: range, newText: rangeNode.description)
        ]
      ]
    )
  )
}

private func makeFlipRangeCodeAction(scope: SyntaxCodeActionScope, rangeNode: Syntax) -> CodeAction? {
  let rangeText = rangeNode.description
  let newText = "(\(rangeText)).reversed()"
  let range = scope.snapshot.range(of: rangeNode)

  return CodeAction(
    title: "Flip range expression",
    kind: .refactorInline,
    edit: WorkspaceEdit(
      changes: [
        scope.snapshot.uri: [
          TextEdit(range: range, newText: newText)
        ]
      ]
    )
  )
}
