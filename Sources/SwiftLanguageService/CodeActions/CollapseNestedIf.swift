//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc.
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftRefactor
import SourceKitLSP
import LanguageServerProtocol

struct CollapseNestedIf: EditRefactoringProvider {
  // MARK: - Required by EditRefactoringProvider

  typealias Input = IfExprSyntax
  typealias Context = Void

  static func textRefactor(
    syntax: IfExprSyntax,
    in context: Void
  ) throws -> [SourceEdit] {
    let statements = syntax.body.statements
    guard
      statements.count == 1,
      let innerIf = statements.first?.item.as(IfExprSyntax.self),
      syntax.elseBody == nil,
      innerIf.elseBody == nil
    else {
      return []
    }

    let combinedConditions = ConditionElementListSyntax(
      Array(syntax.conditions) + Array(innerIf.conditions)
    )

    let newIf = syntax
      .with(\.conditions, combinedConditions)
      .with(\.body, innerIf.body)

    return [
      SourceEdit(
        range: syntax.positionAfterSkippingLeadingTrivia..<syntax.endPosition,
        replacement: newIf.description
      )
    ]
  }
}

// MARK: - Code Action plumbing

extension CollapseNestedIf: SyntaxRefactoringCodeActionProvider {
  static var title: String {
    "Collapse Nested If Statements"
  }

static func nodeToRefactor(
  in scope: SyntaxCodeActionScope
) -> IfExprSyntax? {

  var node: Syntax? = scope.innermostNodeContainingRange

  while let current = node {

    if let ifExpr = current.as(IfExprSyntax.self) {

      // Outer if must not have else
      guard ifExpr.elseBody == nil else { return nil }

      let statements = ifExpr.body.statements
      guard
        statements.count == 1,
        let innerIf = statements.first?.item.as(IfExprSyntax.self),
        innerIf.elseBody == nil
      else {
        return nil
      }

      return ifExpr
    }

    // 🚨 Stop climbing at function / closure boundaries
    if current.is(FunctionDeclSyntax.self)
        || current.is(InitializerDeclSyntax.self)
        || current.is(ClosureExprSyntax.self) {
      break
    }

    node = current.parent
  }

  return nil
}
}

// MARK: - Helpers

private func isTopLevelInCodeBlock(_ ifExpr: IfExprSyntax) -> Bool {
  var current = Syntax(ifExpr)
  if let parent = current.parent,
     parent.is(ExpressionStmtSyntax.self) {
    current = parent
  }
  return current.parent?.is(CodeBlockItemSyntax.self) ?? false
}
