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
@_spi(RawSyntax) @_spi(ExperimentalLanguageFeatures) package import SwiftSyntax

/// Removes redundant parentheses from expressions.
///
/// Examples:
/// - `((x))` -> `x`
/// - `(x)` -> `x` (where x is a simple expression)
///
package struct RemoveRedundantParentheses: SyntaxRefactoringProvider {
  package static func refactor(
    syntax: TupleExprSyntax,
    in context: Void
  ) throws -> ExprSyntax {
    // If the syntax tree has errors, we should not attempt to refactor it.
    guard !syntax.hasError else {
      throw RefactoringNotApplicableError("syntax has errors")
    }

    // Check if the tuple expression has exactly one element and no label.
    guard let innerExpr = syntax.elements.singleUnlabeledExpression else {
      throw RefactoringNotApplicableError("not a parenthesized expression")
    }

    // Case 1: Nested parentheses ((expression)) -> (expression)
    // Recursively strip inner parentheses to handle cases like (((x))) -> x
    if let innerTuple = innerExpr.as(TupleExprSyntax.self) {
      do {
        let refactoredInner = try refactor(syntax: innerTuple, in: ())
        return preserveTrivia(from: syntax, to: refactoredInner)
      } catch {
        // Inner refactoring not applicable (e.g., inner is a multi-element tuple like (x, y)),
        // but we can still remove the outer parentheses around the inner tuple.
        return preserveTrivia(from: syntax, to: innerExpr)
      }
    }

    // Case 2: Parentheses around simple expressions
    if canRemoveParentheses(tuple: syntax, around: innerExpr) {
      return preserveTrivia(from: syntax, to: innerExpr)
    }

    // Default: Parentheses are not redundant
    throw RefactoringNotApplicableError("parentheses are not redundant")
  }

  private static func preserveTrivia(from outer: TupleExprSyntax, to inner: ExprSyntax) -> ExprSyntax {
    let leadingTrivia = outer.leftParen.leadingTrivia
      .merging(outer.leftParen.trailingTrivia)
      .merging(inner.leadingTrivia)
    let trailingTrivia = inner.trailingTrivia
      .merging(outer.rightParen.leadingTrivia)
      .merging(outer.rightParen.trailingTrivia)
    return
      inner
      .with(\.leadingTrivia, leadingTrivia)
      .with(\.trailingTrivia, trailingTrivia)
  }

  private static func canRemoveParentheses(tuple: TupleExprSyntax, around expr: ExprSyntax) -> Bool {
    // Safety Check: Immediately-invoked closures
    // If parent is a FunctionCallExprSyntax and inner expr is a closure, it's an immediately invoked closure.
    // The parentheses are required for disambiguation: `let x = ({ 1 })()` not `let x = { 1 }()`.
    if let parent = tuple.parent, parent.is(FunctionCallExprSyntax.self), expr.is(ClosureExprSyntax.self) {
      return false
    }

    // Safety Check: Ambiguous Closures
    // Closures and trailing closures inside conditions need parentheses to avoid ambiguity.
    // e.g. `if ({ true }) == ({ true }) {}` or `if (call { true }) == false {}`
    // This applies to if/while/guard (ConditionElementSyntax), repeat-while (RepeatStmtSyntax),
    // and where clauses (WhereClauseSyntax).
    // It also applies to InitializerClauseSyntax if it is inside a condition (e.g. `if let x = ({...})`).
    let isInCondition = isInContext(
      tuple,
      keyPaths: [
        \ConditionElementSyntax.condition,
        \RepeatStmtSyntax.condition,
        \WhereClauseSyntax.condition,
      ]
    )

    let isInSwitchSubject = isInContext(tuple, keyPaths: [\SwitchExprSyntax.subject])
    let isInForInSequence = isInContext(tuple, keyPaths: [\ForInStmtSyntax.sequence])

    // Safety Check: Conditions and where clauses
    if isInCondition && requiresParenForAmbiguousClosure(expr) {
      return false
    }

    // Safety Check: Switch subjects
    // `switch { true } {}` is invalid; a closure literal must be parenthesized.
    if isInSwitchSubject && requiresParenForAmbiguousClosure(expr) {
      return false
    }

    // Safety Check: for-in sequences
    // Trailing closures (or IIFEs) in the sequence position should keep parentheses
    // to avoid ambiguity warnings (e.g. `for _ in (call { ... })`).
    if isInForInSequence && requiresParenForAmbiguousClosure(expr) {
      return false
    }

    // Allowlist: Check keyPathInParent to explicitly know that this expression
    // occurs in a place where the parentheses are redundant.
    if let keyPath = tuple.keyPathInParent {
      switch keyPath {
      case \ConditionElementSyntax.condition,
        \InitializerClauseSyntax.value,
        \RepeatStmtSyntax.condition,
        \ReturnStmtSyntax.expression,
        \SwitchExprSyntax.subject,
        \ThrowStmtSyntax.expression:
        return true
      default:
        break
      }
    }

    // Fallback: Allow if the expression itself is "simple"
    guard isSimpleExpression(expr) else {
      return false
    }

    // Safety Check: Postfix and Binary Precedence
    // Expressions like `try`, `await`, `consume`, and `copy` bind looser than postfix and infix expressions.
    // e.g., `(try? f()).description` is different from `try? f().description`.
    // The former accesses `.description` on the Optional result, the latter on the unwrapped value.
    // Similarly, `(try? f()) + 1` is different from `try? f() + 1` (Int? + Int vs Int + Int).
    if let parent = tuple.parent, hasTighterBindingThanEffect(parent) {
      switch expr.as(ExprSyntaxEnum.self) {
      case .tryExpr, .awaitExpr, .unsafeExpr, .consumeExpr, .copyExpr:
        return false
      default:
        break
      }
    }

    return true
  }

  /// Returns true if the node is an expression with higher precedence than effects (try/await/etc).
  /// This includes postfix expressions (member access, subscript, call, force unwrap, optional chaining),
  /// infix operators, type casting (as/is), and ternary expressions.
  private static func hasTighterBindingThanEffect(_ node: Syntax) -> Bool {
    if node.is(ExprListSyntax.self) {
      return true
    }

    guard let expr = node.as(ExprSyntax.self) else {
      return false
    }
    switch expr.as(ExprSyntaxEnum.self) {
    // Postfix expressions: member access, subscript, function call, force unwrap, and postfix operators
    // These all bind tighter than effect expressions (try/await/etc).
    // For member access, since we're a TupleExprSyntax, we are always the base.
    case .memberAccessExpr, .subscriptCallExpr, .functionCallExpr, .forceUnwrapExpr, .postfixOperatorExpr:
      return true

    case .optionalChainingExpr:
      // Optional chaining (?.) binds tighter than effects
      return true

    // Infix operators and sequence expressions bind tighter than effects.
    // For sequence expressions (before SwiftOperators folding), the parent chain
    // is: TupleExpr -> ExprList -> SequenceExpr, e.g., `(try? f()) + 1`.
    case .infixOperatorExpr, .sequenceExpr:
      return true

    // Type casting operators (as, is) bind tighter than effects.
    // Ternary operator also binds tighter than effects.
    case .asExpr, .isExpr, .ternaryExpr:
      return true

    // All other expression types do not bind tighter than effects
    case .arrayExpr, .arrowExpr, .assignmentExpr, .awaitExpr, .binaryOperatorExpr,
      .booleanLiteralExpr, .borrowExpr, ._canImportExpr, ._canImportVersionInfo,
      .closureExpr, .consumeExpr, .copyExpr, .declReferenceExpr, .dictionaryExpr,
      .discardAssignmentExpr, .doExpr, .editorPlaceholderExpr, .floatLiteralExpr,
      .genericSpecializationExpr, .ifExpr, .inOutExpr, .integerLiteralExpr,
      .keyPathExpr, .macroExpansionExpr, .missingExpr, .nilLiteralExpr,
      .packElementExpr, .packExpansionExpr, .patternExpr, .postfixIfConfigExpr,
      .prefixOperatorExpr, .regexLiteralExpr, .simpleStringLiteralExpr,
      .stringLiteralExpr, .superExpr, .switchExpr, .tryExpr, .tupleExpr,
      .typeExpr, .unresolvedAsExpr, .unresolvedIsExpr, .unresolvedTernaryExpr,
      .unsafeExpr:
      return false
    #if RESILIENT_LIBRARIES
    @unknown default:
      return false
    #endif
    }
  }

  private static func hasTrailingClosure(_ expr: ExprSyntax) -> Bool {
    switch expr.as(ExprSyntaxEnum.self) {
    case .functionCallExpr(let functionCall):
      return functionCall.trailingClosure != nil || !functionCall.additionalTrailingClosures.isEmpty
    case .macroExpansionExpr(let macroExpansion):
      return macroExpansion.trailingClosure != nil || !macroExpansion.additionalTrailingClosures.isEmpty
    case .subscriptCallExpr(let subscriptCall):
      return subscriptCall.trailingClosure != nil || !subscriptCall.additionalTrailingClosures.isEmpty
    default:
      return false
    }
  }

  private static func requiresParenForAmbiguousClosure(_ expr: ExprSyntax) -> Bool {
    expr.is(ClosureExprSyntax.self)
      || hasTrailingClosure(expr)
      || isImmediatelyInvokedClosure(expr)
  }

  private static func isInContext(_ tuple: TupleExprSyntax, keyPaths: [AnyKeyPath]) -> Bool {
    return tuple.ancestorOrSelf(mapping: { node in
      if let keyPathInParent = node.keyPathInParent,
        keyPaths.contains(where: { $0 == keyPathInParent })
      {
        return true
      }
      return nil
    }) ?? false
  }

  private static func isImmediatelyInvokedClosure(_ expr: ExprSyntax) -> Bool {
    guard let functionCall = expr.as(FunctionCallExprSyntax.self) else {
      return false
    }
    if functionCall.calledExpression.is(ClosureExprSyntax.self) {
      return true
    }
    if let tuple = functionCall.calledExpression.as(TupleExprSyntax.self),
      tuple.elements.singleUnlabeledExpression?.is(ClosureExprSyntax.self) == true
    {
      return true
    }
    return false
  }

  /// Checks if a type is simple enough to not require parentheses.
  /// Complex types like `any Equatable`, `some P`, or `A & B` need parentheses, e.g. `(any Equatable).self`.
  private static func isSimpleType(_ type: TypeSyntax) -> Bool {
    switch type.as(TypeSyntaxEnum.self) {
    case .arrayType,
      .classRestrictionType,
      .dictionaryType,
      .identifierType,
      .implicitlyUnwrappedOptionalType,
      .inlineArrayType,
      .memberType,
      .metatypeType,
      .missingType,
      .optionalType,
      .tupleType:
      return true
    case .attributedType,  // @escaping, @Sendable, etc.
      .compositionType,  // A & B
      .functionType,  // (A) -> B
      .namedOpaqueReturnType,
      .packElementType,
      .packExpansionType,
      .someOrAnyType,  // some P, any P
      .suppressedType:  // ~Copyable
      return false
    #if RESILIENT_LIBRARIES
    @unknown default:
      return false
    #endif
    }
  }

  private static func isSimpleExpression(_ expr: ExprSyntax) -> Bool {
    // Allowlist of simple expressions that typically don't depend on precedence
    // in a way that requires parentheses when used in most contexts,
    // or are self-contained.
    switch expr.as(ExprSyntaxEnum.self) {
    // Simple expressions that don't require parentheses
    case .arrayExpr,
      .booleanLiteralExpr,
      .closureExpr,
      .declReferenceExpr,
      .dictionaryExpr,
      .floatLiteralExpr,
      .forceUnwrapExpr,
      .integerLiteralExpr,
      .macroExpansionExpr,
      .memberAccessExpr,
      .nilLiteralExpr,
      .optionalChainingExpr,
      .regexLiteralExpr,
      .simpleStringLiteralExpr,
      .stringLiteralExpr,
      .subscriptCallExpr,
      .superExpr:
      return true

    // Types, effects, await, unsafe are simple only if the underlying type is simple
    case .typeExpr(let typeExpr):
      return isSimpleType(typeExpr.type)
    case .awaitExpr(let awaitExpr):
      return isSimpleExpression(awaitExpr.expression)
    case .unsafeExpr(let unsafeExpr):
      return isSimpleExpression(unsafeExpr.expression)

    case .tryExpr(let tryExpr):
      // Only try! and try? are simple; regular try is NOT simple
      // because it affects precedence (e.g., try (try! foo()).bar() vs try try! foo().bar())
      guard tryExpr.questionOrExclamationMark != nil else {
        return false
      }
      return isSimpleExpression(tryExpr.expression)
    case .functionCallExpr(let functionCall):
      // A function call is simple enough to remove parentheses around it.
      // Immediately-invoked closures need parentheses for disambiguation.
      // Without parentheses, `let x = { 1 }()` parses as `let x = { 1 }` followed by `()` as a separate
      // statement, rather than calling the closure. With parentheses: `let x = ({ 1 })()` works correctly.
      return !functionCall.calledExpression.is(ClosureExprSyntax.self)

    // Complex expressions that are NOT simple
    case .arrowExpr,
      .asExpr,
      .assignmentExpr,
      .binaryOperatorExpr,
      .borrowExpr,
      ._canImportExpr,
      ._canImportVersionInfo,
      .consumeExpr,
      .copyExpr,
      .discardAssignmentExpr,
      .doExpr,
      .editorPlaceholderExpr,
      .genericSpecializationExpr,
      .ifExpr,
      .inOutExpr,
      .infixOperatorExpr,
      .isExpr,
      .keyPathExpr,
      .missingExpr,
      .packElementExpr,
      .packExpansionExpr,
      .patternExpr,
      .postfixIfConfigExpr,
      .postfixOperatorExpr,
      .prefixOperatorExpr,
      .sequenceExpr,
      .switchExpr,
      .ternaryExpr,
      .tupleExpr,
      .unresolvedAsExpr,
      .unresolvedIsExpr,
      .unresolvedTernaryExpr:
      return false
    #if RESILIENT_LIBRARIES
    @unknown default:
      return false
    #endif
    }
  }
}
