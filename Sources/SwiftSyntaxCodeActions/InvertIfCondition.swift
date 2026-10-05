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
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Inverts an `if` condition and swaps the branches.
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

    guard let condition = ifExpr.conditions.only else {
      throw RefactoringNotApplicableError("conditions count must be 1")
    }

    guard case .expression(let expr) = condition.condition else {
      throw RefactoringNotApplicableError("condition is not an expression")
    }

    let invertedCondition: ExprSyntax
    if let prefixOpExpr = expr.as(PrefixOperatorExprSyntax.self), prefixOpExpr.operator.text == "!" {
      var innerExpr = prefixOpExpr.expression
      innerExpr.leadingTrivia = prefixOpExpr.leadingTrivia
        .merging(prefixOpExpr.operator.leadingTrivia)
        .merging(prefixOpExpr.operator.trailingTrivia)
        .merging(prefixOpExpr.expression.leadingTrivia)
      invertedCondition = innerExpr
    } else {
      let leadingTrivia = expr.leadingTrivia
      let trailingTrivia = expr.trailingTrivia
      let trimmedExpr = expr.trimmed

      let wrappedInParens = ExprSyntax(
        TupleExprSyntax(
          leftParen: .leftParenToken(),
          elements: LabeledExprListSyntax([
            LabeledExprSyntax(expression: trimmedExpr)
          ]),
          rightParen: .rightParenToken()
        )
      )
      let notExpr = ExprSyntax(
        PrefixOperatorExprSyntax(
          operator: .prefixOperator("!"),
          expression: wrappedInParens
        )
      )

      let transformer = DeMorganTransformer()
      let inverted = transformer.computeComplement(of: notExpr) ?? notExpr

      var finalExpr = inverted
      finalExpr.leadingTrivia = leadingTrivia
      finalExpr.trailingTrivia = trailingTrivia
      invertedCondition = finalExpr
    }

    let newConditions = ifExpr.conditions.with(
      \.[ifExpr.conditions.startIndex].condition,
      .expression(invertedCondition)
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

    let refactoredIfExpr =
      ifExpr
      .with(\.conditions, newConditions)
      .with(\.body, newBody)
      .with(\.elseBody, .codeBlock(newElseBody))

    return removeRedundantParentheses(from: refactoredIfExpr)
  }

  private static func removeRedundantParentheses(from ifExpr: IfExprSyntax) -> IfExprSyntax {
    var current = ifExpr
    while true {
      guard let condition = current.conditions.only,
        case .expression(let expr) = condition.condition
      else {
        break
      }

      if let tuple = expr.as(TupleExprSyntax.self),
        let simplified = try? RemoveRedundantParentheses.refactor(syntax: tuple, in: ())
      {
        current = current.with(
          \.conditions,
          current.conditions.with(
            \.[current.conditions.startIndex].condition,
            .expression(simplified)
          )
        )
        continue
      }

      if let prefixOp = expr.as(PrefixOperatorExprSyntax.self),
        let tuple = prefixOp.expression.as(TupleExprSyntax.self),
        let simplified = try? RemoveRedundantParentheses.refactor(syntax: tuple, in: ())
      {
        var newPrefixOp = prefixOp
        newPrefixOp.expression = simplified
        current = current.with(
          \.conditions,
          current.conditions.with(
            \.[current.conditions.startIndex].condition,
            .expression(ExprSyntax(newPrefixOp))
          )
        )
        continue
      }

      break
    }
    return current
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
