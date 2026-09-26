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
package import SwiftSyntax

/// Inverts a negated `if` condition and swaps the branches.
///
/// ## Before
///
/// ```swift
/// if !x {
///   foo()
/// } else {
///   bar()
/// }
/// ```
///
/// ## After
///
/// ```swift
/// if x {
///   bar()
/// } else {
///   foo()
/// }
/// ```
package struct InvertIfCondition: SyntaxRefactoringProvider {
  package typealias Input = IfExprSyntax
  package typealias Output = IfExprSyntax

  package static func refactor(syntax ifExpr: IfExprSyntax, in context: Void = ()) throws -> IfExprSyntax {
    guard let elseBody = ifExpr.elseBody, case .codeBlock(let elseBlock) = elseBody else {
      throw RefactoringNotApplicableError("missing else block")
    }

    guard ifExpr.conditions.count == 1, let condition = ifExpr.conditions.first else {
      throw RefactoringNotApplicableError("conditions count must be 1")
    }

    guard case .expression(let expr) = condition.condition else {
      throw RefactoringNotApplicableError("condition is not an expression")
    }

    guard let prefixOpExpr = expr.as(PrefixOperatorExprSyntax.self), prefixOpExpr.operator.text == "!" else {
      throw RefactoringNotApplicableError("condition is not negated with '!'")
    }

    let innerExpr = prefixOpExpr.expression.with(
      \.leadingTrivia,
      prefixOpExpr.leadingTrivia
        .merging(prefixOpExpr.operator.leadingTrivia)
        .merging(prefixOpExpr.operator.trailingTrivia)
        .merging(prefixOpExpr.expression.leadingTrivia)
    )

    let newConditions = ifExpr.conditions.with(
      \.[ifExpr.conditions.startIndex].condition,
      .expression(innerExpr)
    )

    let oldBody = ifExpr.body
    let oldElseBlock = elseBlock

    let newBody =
      oldElseBlock
      .with(\.leadingTrivia, oldBody.leadingTrivia)
      .with(\.trailingTrivia, oldBody.trailingTrivia)

    let newElseBody =
      oldBody
      .with(\.leadingTrivia, oldElseBlock.leadingTrivia)
      .with(\.trailingTrivia, oldElseBlock.trailingTrivia)

    return
      ifExpr
      .with(\.conditions, newConditions)
      .with(\.body, newBody)
      .with(\.elseBody, .codeBlock(newElseBody))
  }
}

extension InvertIfCondition: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Invert if condition" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> IfExprSyntax? {
    guard
      let ifExpr = scope.innermostNodeContainingRange?.findParentOfSelf(
        ofType: IfExprSyntax.self,
        stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
      )
    else {
      return nil
    }

    guard (try? refactor(syntax: ifExpr)) != nil else {
      return nil
    }

    return ifExpr
  }
}
