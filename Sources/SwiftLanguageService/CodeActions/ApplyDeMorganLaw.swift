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
import SwiftOperators
package import SwiftSyntax

/// A code action to convert between complement expressions by applying De Morgan's law.
///
/// De Morgan's Law states:
/// - `!(a && b)` = `!a || !b`
/// - `!(a || b)` = `!a && !b`
///
/// This code action supports both boolean (`!`, `&&`, `||`) and bitwise (`~`, `&`, `|`) operators.
struct ApplyDeMorganLaw: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    return DeMorganCandidateSequence(node: node, snapshot: scope.snapshot).compactMap { candidate in
      let transformer = DeMorganTransformer()
      guard let complement = transformer.computeComplement(of: candidate.expr) else {
        return nil
      }

      let complementText = complement.description
      return CodeAction(
        title: "Apply De Morgan's law, converting '\(candidate.expr)' to '\(complementText)'",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: candidate.range,
                newText: complementText
              )
            ]
          ]
        )
      )
    }
  }
}

/// The type of expression, either bitwise or boolean.
private enum ExprType {
  case bitwise
  case boolean

  init?(prefixOperator token: TokenSyntax) {
    switch token.tokenKind {
    case .prefixOperator("~"):
      self = .bitwise
    case .prefixOperator("!"):
      self = .boolean
    default:
      return nil
    }
  }

  init?(binaryOperator tokenKind: TokenKind) {
    switch tokenKind {
    case .binaryOperator("|"), .binaryOperator("&"):
      self = .bitwise
    case .binaryOperator("||"), .binaryOperator("&&"):
      self = .boolean
    default:
      return nil
    }
  }

  var negationPrefix: TokenSyntax {
    switch self {
    case .bitwise:
      return .prefixOperator("~")
    case .boolean:
      return .prefixOperator("!")
    }
  }
}

/// The type of change that occurred during negation.
private enum NegationChange {
  /// Removed a negation prefix (e.g., `!!a` → `a`)
  case denegation
  /// Added a negation prefix
  case negation
  /// Flipped a comparison operator (e.g., `<` → `>=`)
  case comparison
  /// Propagated negation to ternary branches
  case ternary
  /// Changed `&&` to `||`
  case andToOr
  /// Changed `||` to `&&`
  case orToAnd
  /// Substitutes a value (e.g. `true` → `false`)
  case substitution
}

/// Result of negating an expression.
private struct NegatedResult {
  var expr: ExprSyntax
  var change: NegationChange
}

/// A sequence that yields candidate De Morgan expressions by walking up the syntax tree.
private struct DeMorganCandidateSequence: Sequence {
  private let snapshot: DocumentSnapshot
  private var candidates: [ExprSyntax]

  init(node: Syntax, snapshot: DocumentSnapshot) {
    self.snapshot = snapshot
    self.candidates = []

    var current = node.findDeMorganExprParent()
    while let expr = current {
      candidates.append(expr)
      current = expr.parent?.findDeMorganExprParent()
    }
  }

  func makeIterator() -> AnyIterator<(expr: ExprSyntax, range: Range<Position>)> {
    var iterator = candidates.makeIterator()
    return AnyIterator {
      guard let expr = iterator.next() else {
        return nil
      }
      return (expr, snapshot.range(of: expr))
    }
  }
}

/// Encapsulates all De Morgan transformation logic.
package struct DeMorganTransformer {

  package init() {}

  /// Maps AND/OR operators to their flipped counterparts.
  private static let operatorFlipMap: [String: String] = [
    "&&": "||",
    "||": "&&",
    "&": "|",
    "|": "&",
  ]

  /// Maps comparison operators to their negated counterparts.
  private static let comparisonFlipMap: [String: String] = [
    "==": "!=",
    "!=": "==",
    "===": "!==",
    "!==": "===",
    "<": ">=",
    ">": "<=",
    "<=": ">",
    ">=": "<",
  ]

  /// Set of AND operators for precedence checks.
  private static let andOperators: Set<String> = ["&&", "&"]

  /// Computes the complement of a De Morgan expression.
  ///
  /// Uses `SwiftOperators` to fold the expression into a structured form, then attempts
  /// two complement strategies:
  /// 1. Negation expansion: `!(a && b)` → `!a || !b`
  /// 2. Proposition collection: `!a || !b` → `!(a && b)`
  package func computeComplement(of unstructuredExpr: ExprSyntax) -> ExprSyntax? {
    guard
      let structuredExpr = OperatorTable.standardOperators.foldAll(
        unstructuredExpr,
        errorHandler: { _ in }
      ).as(ExprSyntax.self)
    else {
      return nil
    }

    if let result = complementOfNegation(structuredExpr) {
      return result
    }

    if let result = complementOfPropositions(structuredExpr) {
      return result
    }

    return nil
  }

  /// Complements a negation expression: `!(a && b)` → `!a || !b`
  ///
  /// Returns `nil` if the negation didn't simplify (i.e., would just add another negation prefix).
  private func complementOfNegation(_ expr: ExprSyntax) -> ExprSyntax? {
    let inner = expr.lookingThroughParentheses

    guard let prefixExpr = inner.as(PrefixOperatorExprSyntax.self),
      let exprType = ExprType(prefixOperator: prefixExpr.operator)
    else {
      return nil
    }

    guard let negatedContent = negateExpression(prefixExpr.expression, exprType: exprType) else {
      return nil
    }

    if negatedContent.change == .negation {
      return nil
    }

    return mapThroughParentheses(expr, replacement: negatedContent.expr)
  }

  /// Complements propositions: `!a || !b` → `!(a && b)`
  ///
  /// Returns `nil` if neither side simplified (both would just add negation prefixes).
  private func complementOfPropositions(_ expr: ExprSyntax) -> ExprSyntax? {
    let inner = expr.lookingThroughParentheses

    guard let infixExpr = inner.as(InfixOperatorExprSyntax.self),
      let binOp = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
      let exprType = ExprType(binaryOperator: binOp.operator.tokenKind)
    else {
      return nil
    }

    guard let leftNegated = negateExpression(infixExpr.leftOperand, exprType: exprType),
      let rightNegated = negateExpression(infixExpr.rightOperand, exprType: exprType)
    else {
      return nil
    }

    // Prevent applying the transformation if it strictly increases complexity.
    // For example, `a || b` would become `!(!a && !b)`, which adds two negations
    // without simplifying anything. We only proceed if at least one side simplifies.
    guard leftNegated.change != .negation || rightNegated.change != .negation else {
      return nil
    }

    let newOperator = flipOperator(binOp.operator.tokenKind)

    let newInfix =
      infixExpr
      .with(\.leftOperand, parenthesizeIfNeeded(leftNegated, forOperator: newOperator))
      .with(\.operator, ExprSyntax(binOp.with(\.operator.tokenKind, newOperator)))
      .with(\.rightOperand, parenthesizeIfNeeded(rightNegated, forOperator: newOperator))

    let mappedInfix = mapThroughParentheses(expr, replacement: ExprSyntax(newInfix))

    // Transfer leading trivia from the inner expression to the new negation operator
    // so that indentation is preserved and not trapped inside.
    var strippedInfix = mappedInfix
    let leadingTrivia = strippedInfix.leadingTrivia
    if !leadingTrivia.isEmpty {
      strippedInfix = strippedInfix.with(\.leadingTrivia, [])
    }

    let innerExpr: ExprSyntax
    if strippedInfix.isParenthesized {
      innerExpr = strippedInfix
    } else {
      innerExpr = ExprSyntax(
        TupleExprSyntax(
          elements: [LabeledExprSyntax(expression: strippedInfix.with(\.trailingTrivia, []))],
          trailingTrivia: strippedInfix.trailingTrivia
        )
      )
    }

    return ExprSyntax(
      PrefixOperatorExprSyntax(
        operator: exprType.negationPrefix.with(\.leadingTrivia, leadingTrivia),
        expression: innerExpr
      )
    )
  }

  /// Negates an expression according to De Morgan's law.
  ///
  /// Attempts strategies in order: double negation elimination, proposition negation,
  /// comparison flipping, ternary propagation. Falls back to adding a negation prefix.
  private func negateExpression(_ expr: ExprSyntax, exprType: ExprType) -> NegatedResult? {
    let inner = expr.lookingThroughParentheses

    if let result = negateNegation(inner, exprType: exprType) {
      return NegatedResult(expr: mapThroughParentheses(expr, replacement: result.expr), change: result.change)
    }

    if let result = negatePropositions(inner, exprType: exprType) {
      return NegatedResult(expr: mapThroughParentheses(expr, replacement: result.expr), change: result.change)
    }

    if exprType == .boolean, let result = negateComparison(inner) {
      return NegatedResult(expr: mapThroughParentheses(expr, replacement: result.expr), change: result.change)
    }

    if exprType == .boolean, let result = negateBooleanLiteral(inner) {
      return NegatedResult(expr: mapThroughParentheses(expr, replacement: result.expr), change: result.change)
    }

    if let result = negateTernary(inner, exprType: exprType) {
      if result.change == .negation {
        return result
      }
      return NegatedResult(expr: mapThroughParentheses(expr, replacement: result.expr), change: result.change)
    }

    if exprType == .boolean, let result = negateTryAwait(inner, exprType: exprType) {
      return NegatedResult(expr: mapThroughParentheses(expr, replacement: result.expr), change: result.change)
    }

    let negatedExpr = addNegation(to: expr, exprType: exprType)
    return NegatedResult(expr: negatedExpr, change: .negation)
  }

  /// Removes negation from a negated expression (double negation elimination): `!!a` → `a`
  ///
  /// Transfers leading trivia from the removed prefix to the inner expression.
  private func negateNegation(_ expr: ExprSyntax, exprType: ExprType) -> NegatedResult? {
    guard let prefixExpr = expr.as(PrefixOperatorExprSyntax.self),
      let prefixType = ExprType(prefixOperator: prefixExpr.operator),
      prefixType == exprType
    else {
      return nil
    }

    let result = prefixExpr.expression.with(
      \.leadingTrivia,
      prefixExpr.leadingTrivia.merging(prefixExpr.expression.leadingTrivia)
    )

    return NegatedResult(expr: ExprSyntax(result), change: .denegation)
  }

  /// Negates an AND/OR expression: `a && b` → `!a || !b`
  ///
  /// Recursively negates both sides and flips the operator.
  private func negatePropositions(_ expr: ExprSyntax, exprType: ExprType) -> NegatedResult? {
    guard let infixExpr = expr.as(InfixOperatorExprSyntax.self),
      let binOp = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
      let opType = ExprType(binaryOperator: binOp.operator.tokenKind),
      opType == exprType
    else {
      return nil
    }

    guard let leftNegated = negateExpression(infixExpr.leftOperand, exprType: exprType),
      let rightNegated = negateExpression(infixExpr.rightOperand, exprType: exprType)
    else {
      return nil
    }

    let newOperator = flipOperator(binOp.operator.tokenKind)
    let isAndToOr = isAndOperator(binOp.operator.tokenKind)

    let newInfix =
      infixExpr
      .with(\.leftOperand, parenthesizeIfNeeded(leftNegated, forOperator: newOperator))
      .with(\.operator, ExprSyntax(binOp.with(\.operator.tokenKind, newOperator)))
      .with(\.rightOperand, parenthesizeIfNeeded(rightNegated, forOperator: newOperator))

    return NegatedResult(expr: ExprSyntax(newInfix), change: isAndToOr ? .andToOr : .orToAnd)
  }

  /// Flips a comparison operator: `a < b` -> `a >= b`
  private func negateComparison(_ expr: ExprSyntax) -> NegatedResult? {
    guard let infixExpr = expr.as(InfixOperatorExprSyntax.self),
      let binOp = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
      let flipped = Self.comparisonFlipMap[binOp.operator.text]
    else {
      return nil
    }

    let newInfix = infixExpr.with(
      \.operator,
      ExprSyntax(binOp.with(\.operator.tokenKind, .binaryOperator(flipped)))
    )

    return NegatedResult(expr: ExprSyntax(newInfix), change: .comparison)
  }

  /// Negates a boolean literal: `true` → `false`
  private func negateBooleanLiteral(_ expr: ExprSyntax) -> NegatedResult? {
    guard let boolLiteral = expr.as(BooleanLiteralExprSyntax.self) else {
      return nil
    }

    let flippedValue: TokenSyntax
    if boolLiteral.literal.tokenKind == .keyword(.true) {
      flippedValue = .keyword(.false)
    } else if boolLiteral.literal.tokenKind == .keyword(.false) {
      flippedValue = .keyword(.true)
    } else {
      return nil
    }

    let result = boolLiteral.with(
      \.literal,
      flippedValue
        .with(\.leadingTrivia, boolLiteral.literal.leadingTrivia)
        .with(\.trailingTrivia, boolLiteral.literal.trailingTrivia)
    )
    return NegatedResult(expr: ExprSyntax(result), change: .substitution)
  }

  /// Propagates negation through ternary: `a ? b : c` → `a ? !b : !c`
  ///
  /// If both branches would just add negation prefixes, wraps the whole ternary instead: `!(a ? b : c)`
  private func negateTernary(_ expr: ExprSyntax, exprType: ExprType) -> NegatedResult? {
    guard let ternaryExpr = expr.as(TernaryExprSyntax.self) else {
      return nil
    }

    guard let thenNegated = negateExpression(ternaryExpr.thenExpression, exprType: exprType),
      let elseNegated = negateExpression(ternaryExpr.elseExpression, exprType: exprType)
    else {
      return nil
    }

    if thenNegated.change == .negation && elseNegated.change == .negation {
      let negatedExpr = addNegation(to: expr, exprType: exprType)
      return NegatedResult(expr: negatedExpr, change: .negation)
    }

    let newTernary =
      ternaryExpr
      .with(\.thenExpression, thenNegated.expr)
      .with(\.elseExpression, elseNegated.expr)

    return NegatedResult(expr: ExprSyntax(newTernary), change: .ternary)
  }

  /// Propagates negation into try/await expressions: `try a` → `try !a`, `await a` → `await !a`
  ///
  /// This allows negation to flow through these effect markers rather than wrapping them.
  private func negateTryAwait(_ expr: ExprSyntax, exprType: ExprType) -> NegatedResult? {
    // Only handle plain `try`, not `try?` or `try!`.
    // `try?` changes the type to Optional, so negation doesn't propagate.
    // `try!` could propagate, but for simplicity we only handle plain `try`.
    if let tryExpr = expr.as(TryExprSyntax.self), tryExpr.questionOrExclamationMark == nil {
      guard let negatedInner = negateExpression(tryExpr.expression, exprType: exprType) else {
        return nil
      }
      let newTry = tryExpr.with(\.expression, negatedInner.expr)
      return NegatedResult(expr: ExprSyntax(newTry), change: negatedInner.change)
    }

    if let awaitExpr = expr.as(AwaitExprSyntax.self) {
      guard let negatedInner = negateExpression(awaitExpr.expression, exprType: exprType) else {
        return nil
      }
      let newAwait = awaitExpr.with(\.expression, negatedInner.expr)
      return NegatedResult(expr: ExprSyntax(newAwait), change: negatedInner.change)
    }

    return nil
  }

  /// Adds a negation prefix to an expression, wrapping in parentheses if the expression is composite.
  private func addNegation(to expr: ExprSyntax, exprType: ExprType) -> ExprSyntax {
    let needsParens = expr.isComposite && !expr.isParenthesized
    let wrappedExpr: ExprSyntax

    if needsParens {
      wrappedExpr = ExprSyntax(
        TupleExprSyntax(
          elements: [LabeledExprSyntax(expression: expr.with(\.trailingTrivia, []))],
          trailingTrivia: expr.trailingTrivia
        )
      )
    } else {
      wrappedExpr = expr
    }

    var op = exprType.negationPrefix
    // Move leading trivia from the expression to the operator so that indentation is preserved.
    let leadingTrivia = wrappedExpr.leadingTrivia
    if !needsParens && !leadingTrivia.isEmpty {
      op = op.with(\.leadingTrivia, leadingTrivia)
      return ExprSyntax(
        PrefixOperatorExprSyntax(
          operator: op,
          expression: wrappedExpr.with(\.leadingTrivia, [])
        )
      )
    }

    return ExprSyntax(
      PrefixOperatorExprSyntax(
        operator: op,
        expression: wrappedExpr
      )
    )
  }

  /// Flips AND/OR operators using the static mapping.
  private func flipOperator(_ tokenKind: TokenKind) -> TokenKind {
    if case .binaryOperator(let op) = tokenKind,
      let flipped = Self.operatorFlipMap[op]
    {
      return .binaryOperator(flipped)
    }
    return tokenKind
  }

  /// Returns true if the operator is AND.
  private func isAndOperator(_ tokenKind: TokenKind) -> Bool {
    if case .binaryOperator(let op) = tokenKind {
      return Self.andOperators.contains(op)
    }
    return false
  }

  /// Adds parentheses if needed to preserve precedence when the operator changes.
  ///
  /// When the new operator is AND and a subexpression changed from AND→OR,
  /// parentheses are required to maintain correct precedence.
  private func parenthesizeIfNeeded(
    _ result: NegatedResult,
    forOperator newOp: TokenKind
  ) -> ExprSyntax {
    if isAndOperator(newOp) && result.change == .andToOr && !result.expr.is(TupleExprSyntax.self) {
      return ExprSyntax(
        TupleExprSyntax(
          elements: [LabeledExprSyntax(expression: result.expr.with(\.trailingTrivia, []))],
          trailingTrivia: result.expr.trailingTrivia
        )
      )
    }
    return result.expr
  }
}

/// Maps a replacement through parentheses, preserving the outer structure.
private func mapThroughParentheses(_ expr: ExprSyntax, replacement: ExprSyntax) -> ExprSyntax {
  if let tuple = expr.as(TupleExprSyntax.self),
    let inner = tuple.singleUnlabeledExpression
  {
    let mappedInner = mapThroughParentheses(inner, replacement: replacement)
    return ExprSyntax(
      tuple.with(\.elements, [LabeledExprSyntax(expression: mappedInner)])
    )
  }
  return replacement
}

fileprivate extension ExprSyntax {
  /// Returns the expression looking through parentheses.
  var lookingThroughParentheses: ExprSyntax {
    if let inner = self.as(TupleExprSyntax.self)?.singleUnlabeledExpression {
      return inner.lookingThroughParentheses
    }
    return self
  }

  /// Returns true if this expression is wrapped in parentheses.
  var isParenthesized: Bool {
    self.as(TupleExprSyntax.self)?.isParentheses ?? false
  }

  /// Returns true if this is a composite expression that needs parentheses when negated.
  ///
  /// Safe-by-default behavior: explicitly lists atomic types that do NOT need parentheses.
  /// All other types (including future language additions) default to true to ensure correctness.
  var isComposite: Bool {
    switch self.kind {
    case .arrayExpr, .booleanLiteralExpr, .closureExpr, .declReferenceExpr, .dictionaryExpr, .discardAssignmentExpr,
      .floatLiteralExpr, .forceUnwrapExpr, .functionCallExpr, .integerLiteralExpr, .keyPathExpr, .macroExpansionExpr,
      .memberAccessExpr, .nilLiteralExpr, .optionalChainingExpr, .postfixOperatorExpr, .prefixOperatorExpr,
      .regexLiteralExpr, .stringLiteralExpr, .subscriptCallExpr, .superExpr, .tupleExpr:
      return false
    default:
      return true
    }
  }
}

fileprivate extension TupleExprSyntax {
  /// Returns true if this is a parenthesized expression (single unlabeled element).
  var isParentheses: Bool {
    singleUnlabeledExpression != nil
  }

  /// Returns the single unlabeled expression if this is a parenthesized expression.
  var singleUnlabeledExpression: ExprSyntax? {
    guard let only = elements.only, only.label == nil else {
      return nil
    }
    return only.expression
  }
}

fileprivate extension Syntax {
  /// Finds the nearest ancestor that is a valid De Morgan expression candidate.
  func findDeMorganExprParent() -> ExprSyntax? {
    findParentOfSelf(
      ofType: ExprSyntax.self,
      stoppingIf: { syntax in
        syntax.kind == .codeBlockItem || syntax.kind == .memberBlockItem || syntax.kind == .conditionElement
      }
    )
  }
}
