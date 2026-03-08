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
struct FlipRangeExpression: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    // Use the token at the start of the range so we find the expression that contains
    // the selection even when the range end is exactly at the expression boundary
    // (otherwise the right token can be the next token and the common ancestor is too high).
    guard let startToken = scope.file.token(at: scope.range.lowerBound) else {
      return []
    }
    let node = Syntax(startToken)

    if let action = flipStride(scope: scope, from: node) {
      return [action]
    }
    if let action = flipRangeOperator(scope: scope, from: node) {
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

/// Returns the source text for the negated stride step (e.g. "1" → "-1", "x" → "-(x)").
private func negateStrideStepText(_ expr: ExprSyntax) -> String {
  let inner = expr.lookingThroughParentheses

  if let intLit = inner.as(IntegerLiteralExprSyntax.self) {
    let raw = intLit.literal.text.filter { $0 != "_" }
    if let value = Int(raw, radix: 10) {
      return (-value).description
    }
  }

  if let floatLit = inner.as(FloatLiteralExprSyntax.self),
    let value = Double(floatLit.literal.text)
  {
    return (-value).description
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

  var needParensForPrefixMinus: Bool {
    switch self.kind {
    case .infixOperatorExpr, .sequenceExpr, .ternaryExpr, .binaryOperatorExpr:
      return true
    default:
      return false
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
private func flipRangeOperator(scope: SyntaxCodeActionScope, from node: Syntax) -> CodeAction? {
  if let action = flipRangeInfix(scope: scope, from: node) {
    return action
  }
  return flipRangeSequence(scope: scope, from: node)
}

private func flipRangeInfix(scope: SyntaxCodeActionScope, from node: Syntax) -> CodeAction? {
  guard let infix = node.findParentOfSelf(
    ofType: InfixOperatorExprSyntax.self,
    stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
  ) else {
    return nil
  }

  guard let binOp = infix.operator.as(BinaryOperatorExprSyntax.self) else {
    return nil
  }
  let opText = binOp.operator.text
  guard opText == "..." || opText == "..<" else {
    return nil
  }

  return makeFlipRangeCodeAction(scope: scope, rangeNode: Syntax(infix))
}

private func flipRangeSequence(scope: SyntaxCodeActionScope, from node: Syntax) -> CodeAction? {
  guard let seq = node.findParentOfSelf(
    ofType: SequenceExprSyntax.self,
    stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
  ) else {
    return nil
  }

  let elements = seq.elements
  guard elements.count == 3,
    let middleExpr = elements.dropFirst(1).first,
    let binOp = middleExpr.as(BinaryOperatorExprSyntax.self)
  else {
    return nil
  }
  let opText = binOp.operator.text
  guard opText == "..." || opText == "..<" else {
    return nil
  }

  return makeFlipRangeCodeAction(scope: scope, rangeNode: Syntax(seq))
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
