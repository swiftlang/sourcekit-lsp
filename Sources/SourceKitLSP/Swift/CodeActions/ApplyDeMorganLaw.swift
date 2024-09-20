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

import LanguageServerProtocol
import SwiftOperators
import SwiftRefactor
import SwiftSyntax

/// A code action to convert between complement expressions by applying the De Morgan's law.
struct ApplyDeMorganLaw: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange,
      let deMorganExprs = DeMorgan.Sequence(node: node, snapshot: scope.snapshot)
    else {
      return []
    }

    for (deMorganExpr, sourceRange) in deMorganExprs {
      guard let rootExpr = DeMorgan.RootExpr(unstructuredExpr: deMorganExpr),
        let deMorganComplement = rootExpr.complement()
      else {
        continue
      }

      let deMorganComplementText = "\(deMorganComplement)"
      return [
        CodeAction(
          title: "Convert \(deMorganExpr) to \(deMorganComplementText)",
          kind: .refactorInline,
          edit: WorkspaceEdit(
            changes: [
              scope.snapshot.uri: [
                TextEdit(
                  range: sourceRange,
                  newText: deMorganComplementText
                )
              ]
            ]
          )
        )
      ]
    }

    return []
  }
}

/// A pseudo namespace for all facilities necessary for DeMorgan conversion.
private enum DeMorgan {
  /// A sequence yielding DeMorgan complement expressions lazily.
  struct Sequence: Swift.Sequence, IteratorProtocol {
    var snapshot: DocumentSnapshot
    var sequence: [ExprSyntax]

    ///  Constructs a stack of candidate expressions by recursively visiting and pushing `node`'s ancestor
    ///  expressions to the stack until we reach the code boundary.
    ///
    ///  We use a stack here because we want to apply DeMorgan to the expression as widely scoped as possible. On each
    ///  iteration, the sequence will continue popping the stack until a potential candidate expression is found.
    init?(node: Syntax, snapshot: DocumentSnapshot) {
      guard var node = node.findDeMorganExprParentOfSelf else {
        return nil
      }
      self.snapshot = snapshot
      self.sequence = [node]
      while let parent = node.parent?.findDeMorganExprParentOfSelf {
        self.sequence.append(parent)
        node = parent
      }
    }

    mutating func next() -> (deMorganExpr: ExprSyntax, sourceRange: Range<Position>)? {
      self.sequence.popLast()?.preflight(snapshot: self.snapshot)
    }

    func makeIterator() -> Self {
      self
    }
  }

  /// A root level expression. The only two forms of an `RootExpr` which are valid for DeMorgan conversion are
  /// propositions and the negation of propositions.
  ///
  /// Instances of propositions are valid AND/OR expressions, bitwise or boolean,
  /// ```swift
  /// a && b // boolean AND expression
  /// a && b || c // boolean OR expression
  /// ((a && ((b)) || (c))) // boolean OR expression, regardless of extraneous parentheses
  /// ((a & ((b)) | (c))) // bitwise OR expression
  /// ```
  ///
  /// In a negation of propositions, the negation prefix must be in agreement with the binary operator, i.e.
  /// ```swift
  /// // valid
  /// !(a && b) // ! agrees with &&, both boolean
  /// ~(a | b) // ~ agrees with |, both bitwise
  /// ((~(((a | b))))) // regardless of extraneous parentheses
  ///
  /// // invalid
  /// !(a & b) // ! doesn't agree with &
  /// ~(a || b) // ~ doesn't agree with ||
  /// ```
  ///
  /// The complement of a root-level propositions is always a negation,
  /// ```swift
  /// !a && b /* complements with */ !(a || !b)
  /// ~a | ~b /* complements with */ ~(a & b)
  /// ```
  /// - Note: The unproductive conversion from `a AND/OR b` -> `NOT(NOT a OR/AND NOT b)` is not supported.
  ///
  /// The complement of a root-level negation of propositions is always propositions.
  /// ```swift
  /// !(a && b) /* complements with */ (!a || !b)
  /// ~(~a | ~b) /* becomes */ (a & b)
  /// ```
  struct RootExpr {
    private var expr: Expr

    /// Attempts to fold `unstructuredExpr` into a structured expression using `SwiftOperators` and stores the result.
    init?(unstructuredExpr: ExprSyntax) {
      if let structuredExpr = OperatorTable.standardOperators.foldAll(
        unstructuredExpr,
        errorHandler: { _ in
        }
      ).as(ExprSyntax.self) {
        self.expr = Expr(expr: structuredExpr)
      } else {
        return nil
      }
    }

    /// Returns the complement of the expression stored, if any.
    func complement() -> ExprSyntax? {
      self.complementOfNegation() ?? self.complementOfPropositions()
    }

    /// Returns the complement of the expression stored by treating it as a negation, if any.
    private func complementOfNegation() -> ExprSyntax? {
      if let prefixExpr = self.expr.as(PrefixOperatorExprSyntax.self),
        let negation = Negation(prefixExpr),
        let complement = Expr(expr: negation.expr).negatedPropositions(exprType: negation.exprType)
      {
        // TODO: remove parentheses?
        self.expr.map(negatedExpr: complement.expr)
      } else {
        nil
      }
    }

    /// Returns the complement of the expression stored by treating it as propositions, if any.
    private func complementOfPropositions() -> ExprSyntax? {
      if let infixExpr = self.expr.as(InfixOperatorExprSyntax.self),
        let propositions = NegatedPropositions(infixExpr)
      {
        self.expr.map(
          negation: Negation(
            exprType: propositions.operator.exprType,
            expr: propositions.expr
          )
        ).expr
      } else {
        nil
      }
    }
  }

  /// The type of expression, either bitwise or boolean.
  private enum ExprType {
    case bitwise
    case boolean

    init?(operator: TokenSyntax) {
      switch `operator`.tokenKind {
      case .prefixOperator("~"):
        self = .bitwise
      case .prefixOperator("!"):
        self = .boolean
      default:
        return nil
      }
    }

    var negationPrefix: TokenSyntax {
      switch self {
      case .bitwise:
        .prefixOperator("~")
      case .boolean:
        .prefixOperator("!")
      }
    }
  }

  /// An expression wrapper abstracting away any presence of extraneous parentheses in the given expression, exposing
  /// only the expression of interest for easier manipulation.
  private enum Expr {
    /// A single means a tuple containing only one element, implying that there exists at least one pair of extraneous
    /// parentheses enclosing the expression of interest.
    ///
    /// - Parameters:
    ///   - desinglified: The first non-single descendent expression. The expression of interest.
    case single(TupleExprSyntax, desinglified: ExprSyntax)
    /// A non-single expression at its root. The expression of interest.
    case other(ExprSyntax)

    /// The types of change taken place in a negation.
    enum Change {
      /// The negation prefix was stripped.
      case denegation
      /// A negation prefix was added.
      case negation
      /// The comparison operator was flipped.
      case comparison
      /// A ternary propagation took place.
      case ternary
      /// The binary operator was changed from AND to OR.
      case andToOr
      /// The binary operator was changed from OR to AND.
      case orToAnd
    }

    typealias Negated = (expr: ExprSyntax, change: Change)

    init(expr: ExprSyntax) {
      if let tuple = expr.as(TupleExprSyntax.self),
        let only = tuple.elements.only
      {
        switch Self(expr: only.expression) {
        case .single(_, let desinglified), .other(let desinglified):
          self = .single(tuple, desinglified: desinglified)
        }
      } else {
        self = .other(expr)
      }
    }

    /// Negates the expression of interest, maps the negated expression with the single ancestor if any, and returns
    /// the result.
    ///
    /// - Parameters:
    ///   - exprType: The type of expression that this and all recursive negations must agree with.
    ///
    /// - Returns: The orignal expression negated, and the type of the outermost change taken place.
    func negated(exprType: ExprType) -> Negated {
      if let complementOfNegation = self.negatedNegation(exprType: exprType) {
        return complementOfNegation
      }
      if let complementOfPropositions = self.negatedPropositions(exprType: exprType) {
        return complementOfPropositions
      }
      if let complementOfComparison = self.negatedComparison(exprType: exprType) {
        return complementOfComparison
      }
      if let complementOfTernary = self.negatedTernary(exprType: exprType) {
        return complementOfTernary
      }
      return self.map(negation: Negation(exprType: exprType, expr: self.exprOfInterest))
    }

    /// If the expression of interest is a negation expression, returns the negated expression and the type of change
    /// as `Change.denegation`.
    ///
    /// The only valid form of a negation expression is `NOT Expr`,
    /// ```swift
    /// // boolean
    /// !a, !true
    /// !(a && b), !(a || b)
    /// !(a is Int), !(b as! Bool), !(a >= b), !(a ? true : false)
    ///
    /// // bitwise
    /// ~b, ~0
    /// ~(a | b), ~(a & b)
    /// ~(a as Int), ~(b << 1), ~(a ? 1 : 0)
    /// ```
    ///
    /// - Note: A valid negation expression must have its prefix agree with `exprType`.
    func negatedNegation(exprType: ExprType) -> Negated? {
      if let prefixExpr = self.as(PrefixOperatorExprSyntax.self),
        let negatedNegation = Negation(prefixExpr, exprType: exprType)
      {
        // TODO: remove parentheses?
        (self.map(negatedExpr: negatedNegation.expr), .denegation)
      } else {
        nil
      }
    }

    /// If the expression of interest is propositions, returns its negated expression and the type of change as either
    /// `Change.orToAnd` or `Change.andToOr`.
    ///
    /// - Note: A valid instance of propositions must have its binary operator agree with `exprType`.
    func negatedPropositions(exprType: ExprType) -> Negated? {
      if let infixExpr = self.as(InfixOperatorExprSyntax.self),
        let negatedPropositions = NegatedPropositions(infixExpr, exprType: exprType)
      {
        (
          self.map(negatedExpr: negatedPropositions.expr),
          negatedPropositions.operator.kind == .and ? .orToAnd : .andToOr
        )
      } else {
        nil
      }
    }

    /// If the expression of interest is a comparison expression, returns its negated expression and the type of
    /// change as `Change.comparison`.
    ///
    /// Comparison expressions only exist when `exprType == .boolean`. The negated expression is formed by flipping
    /// the comparison operator to its negated counterpart. e.g.,
    ///
    /// ```swift
    /// a < b /* negated to */ a >= b
    /// a !== b /* negated to */ a === b
    /// ```
    func negatedComparison(exprType: ExprType) -> Negated? {
      guard exprType == .boolean,
        let infixExpr = self.as(InfixOperatorExprSyntax.self)
      else {
        return nil
      }
      let biOperator = infixExpr.biOperator

      guard let comparisonOperator = ComparisonOperator(rawValue: biOperator.operator.text) else {
        return nil
      }

      let negatedExpr = ExprSyntax(
        infixExpr.with(
          \.operator,
          ExprSyntax(biOperator.with(\.operator.tokenKind, .binaryOperator(comparisonOperator.negated.rawValue)))
        )
      )

      return (self.map(negatedExpr: negatedExpr), .comparison)
    }

    /// If the expression of interest is a ternary expression, returns its negated expression and the type of change as
    /// either `Change.negation` or `Change.ternary`.
    ///
    /// A ternary expression is negated to a negation expression if both of its sub-expressions will become negation
    /// expressions upon negation, e.g.
    /// ```swift
    /// // prefer
    /// (a ? b : c) /* negated to */ !(a ? b : c)
    /// // rather than
    /// (a ? b : c) /* negated to */ (a ? !b : !c)
    /// ```
    ///
    /// Otherwise the negation will propagate to its sub-expressions, e.g.
    /// ```swift
    /// (a ? !b : c) /* negated to */ (a ? b : !c)
    /// (a ? !b : !c) /* negated to */ (a ? b : c)
    /// ```
    func negatedTernary(exprType: ExprType) -> Negated? {
      if let ternaryExpr = self.as(TernaryExprSyntax.self) {
        switch NegatedTernary(ternaryExpr, exprType: exprType) {
        case .negation(let negation):
          self.map(negation: negation)
        case .ternary(let ternary):
          (self.map(negatedExpr: ternary), .ternary)
        }
      } else {
        nil
      }
    }

    /// The expression of interest for manipulation.
    var exprOfInterest: ExprSyntax {
      switch self {
      case .single(_, let exprOfInterest), .other(let exprOfInterest):
        exprOfInterest
      }
    }

    /// Downcasts the expression of interest as the given `type`.
    func `as`<E: ExprSyntaxProtocol>(_ type: E.Type) -> E? {
      self.exprOfInterest.as(E.self)
    }

    /// Substitutes the expression of interest with the negated expression, prepend the negation prefix, and returns
    /// the result.
    ///
    /// To avoid creating extraneous parentheses, we only add a pair of parantheses to the negated expression when,
    ///  1. The negated expression is a composite expression, and
    ///  2. The original expression is not a single.
    ///
    /// - Note: A composite expression is one of `AsExprSyntax`, `AwaitExprSyntax`, `InfixOperatorExprSyntax`,
    /// `IsExprSyntax`, or `TryExprSyntax`.
    ///
    /// An example of mapping is as follows,
    /// ```swift
    /// // original expression
    /// ((!a || b is String))
    /// // expression of interest
    /// !a || b is String
    /// !a /* negated to and mapped to */ a
    /// b is String /* negated to */ Negation(b is String) /* mapped to */ !(b is String)
    /// // negated expression of interest
    /// a && !(b is String)
    /// // mapped to
    /// !((a && !(b is String)))
    /// ```
    func map(negation: Negation) -> Negated {
      let negatedExpr =
        switch self {
        case .single(let tuple, _):
          PrefixOperatorExprSyntax(
            operator: negation.exprType.negationPrefix,
            expression: tuple.map(complementExpr: negation.expr)
          )
        case .other:
          PrefixOperatorExprSyntax(
            operator: negation.exprType.negationPrefix,
            expression: negation.expr.isComposite
              ? ExprSyntax(TupleExprSyntax(onlyExpr: negation.expr)) : negation.expr
          )
        }
      return (ExprSyntax(negatedExpr), .negation)
    }

    /// Substitutes the expression of interest with the negated expression and returns the result.
    func map(negatedExpr: some ExprSyntaxProtocol) -> ExprSyntax {
      switch self {
      case .single(let tuple, _):
        ExprSyntax(tuple.map(complementExpr: ExprSyntax(negatedExpr)))
      case .other:
        ExprSyntax(negatedExpr)
      }
    }
  }

  /// Represents a negation expression with `expr` being its only sub-expression.
  private struct Negation {
    var exprType: ExprType
    var expr: ExprSyntax

    init(exprType: ExprType, expr: some ExprSyntaxProtocol) {
      self.exprType = exprType
      self.expr = ExprSyntax(expr)
    }

    /// If `exprType` is `nil`, this indicates the negation expression is at the root-level and `exprType` will be
    /// inferred from the prefix of `prefixExpr`. Otherwise `prefixExpr` will be checked for its prefix's agreement
    /// with the given `exprType`.
    init?(_ prefixExpr: PrefixOperatorExprSyntax, exprType: ExprType? = nil) {
      guard let localExprType = ExprType(operator: prefixExpr.operator) else {
        return nil
      }
      if let exprType, exprType != localExprType {
        return nil
      }
      self.init(
        exprType: localExprType,
        expr: prefixExpr.expression.with(
          \.leadingTrivia,
          prefixExpr.leadingTrivia + prefixExpr.expression.leadingTrivia
        )
      )
    }
  }

  /// Represents the negated expression of an instance of propositions.
  private struct NegatedPropositions {
    struct Operator {
      enum Kind {
        case and
        case or

        var complement: Self {
          switch self {
          case .and:
            .or
          case .or:
            .and
          }
        }
      }
      var kind: Kind
      var exprType: ExprType

      init(kind: Kind, exprType: ExprType) {
        self.kind = kind
        self.exprType = exprType
      }

      init?(_ tokenKind: TokenKind) {
        switch tokenKind {
        case .binaryOperator("|"):
          self.init(kind: .or, exprType: .bitwise)
        case .binaryOperator("&"):
          self.init(kind: .and, exprType: .bitwise)
        case .binaryOperator("||"):
          self.init(kind: .or, exprType: .boolean)
        case .binaryOperator("&&"):
          self.init(kind: .and, exprType: .boolean)
        default:
          return nil
        }
      }

      var complement: Self {
        Self(kind: self.kind.complement, exprType: self.exprType)
      }

      var tokenKind: TokenKind {
        switch (self.kind, self.exprType) {
        case (.and, .boolean):
          .binaryOperator("&&")
        case (.or, .boolean):
          .binaryOperator("||")
        case (.and, .bitwise):
          .binaryOperator("&")
        case (.or, .bitwise):
          .binaryOperator("|")
        }
      }
    }

    /// The binary operator of this negated expression.
    var `operator`: Operator
    /// The negated expression.
    var expr: InfixOperatorExprSyntax

    /// Constructs the negated expression of the given `infixExpr` if it is propositions.
    ///
    /// If `exprType` is `nil`, this indicates `infixExpr` is at the root-level and `exprType` will be inferred from
    /// the type of the binary operator.
    /// - Note: The form `a AND/OR b /* negated to */ NOT a OR/AND NOT b` is considered unproductive at the root-level
    /// thus not supported, e.g. `a || b /* negated to */ !a && !b`.
    ///
    /// Otherwise, `infixExpr` will be checked for its binary operator's agreement with the given `exprType`.
    ///
    /// To preserve precedence order, a subexpression of the negated expression will be enclosed with an extra pair of
    /// parentheses if,
    ///   1. The negated expression has flipped from OR to AND, and
    ///   2. The subexpression has flipped from AND to OR, and
    ///   3. The subexpression is not `TupleExprSyntax`.
    ///
    /// The necessity of such parenthesising can be seen as follows,
    /// ```swift
    /// a && b || c /* negated to */ (!a || !b) && !c
    /// ```
    init?(_ infixExpr: InfixOperatorExprSyntax, exprType: ExprType? = nil) {
      let biOperator = infixExpr.biOperator
      guard let `operator` = Operator(biOperator.operator.tokenKind)?.complement else {
        return nil
      }
      self.operator = `operator`

      func exprParenthesizedIfNeeded(_ negated: Expr.Negated) -> ExprSyntax {
        if `operator`.kind == .and && negated.change == .andToOr && !negated.expr.is(TupleExprSyntax.self) {
          ExprSyntax(TupleExprSyntax(onlyExpr: negated.expr))
        } else {
          negated.expr
        }
      }

      let leftNegated: Expr.Negated
      let rightNegated: Expr.Negated
      if let exprType {
        guard self.operator.exprType == exprType else {
          return nil
        }
        leftNegated = Expr(expr: infixExpr.leftOperand).negated(exprType: self.operator.exprType)
        rightNegated = Expr(expr: infixExpr.rightOperand).negated(exprType: self.operator.exprType)
      } else {
        leftNegated = Expr(expr: infixExpr.leftOperand).negated(exprType: self.operator.exprType)
        rightNegated = Expr(expr: infixExpr.rightOperand).negated(exprType: self.operator.exprType)
        guard leftNegated.change != .negation || rightNegated.change != .negation else {
          // a || b -> !(!a && !b) is undesirable at the root level
          return nil
        }
      }

      self.expr = infixExpr.with(\.leftOperand, exprParenthesizedIfNeeded(leftNegated))
        .with(\.operator, ExprSyntax(biOperator.with(\.operator.tokenKind, self.operator.tokenKind)))
        .with(\.rightOperand, exprParenthesizedIfNeeded(rightNegated))
    }
  }

  private enum ComparisonOperator: String {
    case equal = "=="
    case notEqual = "!="
    case equalReference = "==="
    case notEqualReference = "!=="
    case lessThan = "<"
    case greaterThan = ">"
    case lessThanOrEqual = "<="
    case greaterThanOrEqual = ">="

    var negated: Self {
      switch self {
      case .equal:
        .notEqual
      case .notEqual:
        .equal
      case .equalReference:
        .notEqualReference
      case .notEqualReference:
        .equalReference
      case .lessThan:
        .greaterThanOrEqual
      case .greaterThan:
        .lessThanOrEqual
      case .lessThanOrEqual:
        .greaterThan
      case .greaterThanOrEqual:
        .lessThan
      }
    }
  }

  private enum NegatedTernary {
    case negation(Negation)
    case ternary(TernaryExprSyntax)

    init(_ ternaryExpr: TernaryExprSyntax, exprType: ExprType) {
      let thenComplement = Expr(expr: ternaryExpr.thenExpression).negated(exprType: exprType)
      let elseComplement = Expr(expr: ternaryExpr.elseExpression).negated(exprType: exprType)

      if thenComplement.change == .negation && elseComplement.change == .negation {
        self = .negation(Negation(exprType: exprType, expr: ternaryExpr))
      } else {
        self = .ternary(
          ternaryExpr.with(\.thenExpression, thenComplement.expr).with(\.elseExpression, elseComplement.expr)
        )
      }
    }
  }
}

fileprivate extension ExprSyntax {
  /// if this node is SequenceExprSyntax and its elements contain an AssignmentExpr,
  /// extracts all elements right to the AssignmentExpr and computes the extracted range,
  /// otherwise it is a no-op.
  ///
  ///  For example, we extract
  ///
  ///     b && c
  ///
  ///  from
  ///
  ///     a = b && c
  func preflight(snapshot: DocumentSnapshot) -> (ExprSyntax, Range<Position>) {
    let range = snapshot.range(of: self)

    guard let seqExpr = self.as(SequenceExprSyntax.self) else {
      return (self, range)
    }

    let seqElements = seqExpr.elements
    guard
      let assignmentExprIdx = (seqElements.firstIndex { $0.kind == .assignmentExpr })
    else {
      return (self, range)
    }

    let slicingIndex = seqElements.index(after: assignmentExprIdx)
    guard slicingIndex < seqElements.endIndex else {
      return (self, range)
    }

    return (
      ExprSyntax(
        SequenceExprSyntax(
          elements: ExprListSyntax(seqElements[slicingIndex...]),
          seqExpr.unexpectedAfterElements,
          trailingTrivia: seqExpr.trailingTrivia
        )
      )!, snapshot.range(of: seqElements[slicingIndex]).lowerBound..<range.upperBound
    )
  }

  var isComposite: Bool {
    switch self.kind {
    case .asExpr, .awaitExpr, .infixOperatorExpr, .isExpr, .tryExpr:
      true
    default:
      false
    }
  }
}

private extension LabeledExprListSyntax.Element {
  var single: TupleExprSyntax? {
    self.expression.as(TupleExprSyntax.self)
  }
}

private extension SyntaxProtocol {
  var findDeMorganExprParentOfSelf: ExprSyntax? {
    self.findParentOfSelf(
      ofType: ExprSyntax.self,
      stoppingIf: { syntax in
        syntax.kind == .codeBlockItem || syntax.kind == .memberBlockItem || syntax.kind == .conditionElement
      }
    )
  }
}

private extension InfixOperatorExprSyntax {
  var biOperator: BinaryOperatorExprSyntax {
    self.operator.cast(BinaryOperatorExprSyntax.self)
  }
}

private extension TupleExprSyntax {
  init(onlyExpr: ExprSyntax) {
    self.init(
      elements: [LabeledExprSyntax(expression: onlyExpr.with(\.trailingTrivia, []))],
      trailingTrivia: onlyExpr.trailingTrivia
    )
  }

  func map(complementExpr: ExprSyntax) -> Self {
    if let single = self.elements.only?.single {
      self.with(\.elements, [LabeledExprSyntax(expression: single.map(complementExpr: complementExpr))])
    } else {
      self.with(\.elements, [LabeledExprSyntax(expression: complementExpr)])
    }
  }
}
