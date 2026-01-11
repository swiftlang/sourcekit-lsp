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

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftBasicFormat
import SwiftExtensions
import SwiftSyntax
import SwiftSyntaxBuilder

/// Syntactic code action provider to convert an if-let with early-exit pattern to a guard-let statement.
///
/// ## Before
/// ```swift
/// if let value = optional {
///   // use value
///   return value
/// }
/// return nil
/// ```
///
/// ## After
/// ```swift
/// guard let value = optional else {
///   return nil
/// }
/// // use value
/// return value
/// ```
@_spi(Testing) public struct ConvertIfLetToGuard: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let ifExpr = findConvertibleIfExpr(in: scope) else {
      return []
    }

    var current = Syntax(ifExpr)
    if let parent = current.parent, parent.is(ExpressionStmtSyntax.self) {
      current = parent
    }

    guard current.parent?.is(CodeBlockItemSyntax.self) ?? false else {
      return []
    }

    guard let codeBlockItem = current.parent?.as(CodeBlockItemSyntax.self),
      let codeBlockItemList = codeBlockItem.parent?.as(CodeBlockItemListSyntax.self)
    else {
      return []
    }

    guard let ifIndex = codeBlockItemList.index(of: codeBlockItem) else {
      return []
    }

    let followingStatements = codeBlockItemList[codeBlockItemList.index(after: ifIndex)...]
    guard let lastStatement = followingStatements.last else {
      return []
    }

    let baseIndentation = ifExpr.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    let indentStep = BasicFormat.inferIndentation(of: ifExpr.root) ?? .spaces(4)

    let guardStmt = buildGuardStatement(
      from: ifExpr,
      elseBody: Array(followingStatements),
      baseIndentation: baseIndentation,
      indentStep: indentStep
    )
    let newBodyStatements = ifExpr.body.statements

    var replacementText = guardStmt.description

    let remover = IndentationRemover(indentation: indentStep)
    for (index, stmt) in newBodyStatements.enumerated() {
      var adjustedStmt = remover.rewrite(stmt)
      if index == 0 {
        // The first statement moved out of the if-block should be placed on a new line
        // at the base indentation level. We strip any leading newlines and indentation
        // and replace them with a single newline + base indentation.
        let pieces = adjustedStmt.leadingTrivia.drop(while: \.isWhitespace)
        adjustedStmt.leadingTrivia = .newline + baseIndentation + Trivia(pieces: Array(pieces))
      }
      replacementText += adjustedStmt.description
    }

    let edit = TextEdit(
      range: scope.snapshot.absolutePositionRange(of: ifExpr.positionAfterSkippingLeadingTrivia..<lastStatement.endPosition),
      newText: replacementText
    )

    return [
      CodeAction(
        title: "Convert to guard",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  private static func findConvertibleIfExpr(in scope: SyntaxCodeActionScope) -> IfExprSyntax? {
    var node: Syntax? = scope.innermostNodeContainingRange
    while let c = node, !isFunctionBoundary(c) {
      if let ifExpr = c.as(IfExprSyntax.self) {
        if isConvertibleToGuard(ifExpr) && isTopLevelInCodeBlock(ifExpr) {
          return ifExpr
        }
        // If we found an IfExpr but it's not the one we want, stop here
        // to avoid picking an outer one when the user is in an inner expression-if.
        return nil
      }
      node = c.parent
    }
    return nil
  }

  private static func isTopLevelInCodeBlock(_ ifExpr: IfExprSyntax) -> Bool {
    var current = Syntax(ifExpr)
    if let parent = current.parent, parent.is(ExpressionStmtSyntax.self) {
      current = parent
    }
    return current.parent?.is(CodeBlockItemSyntax.self) ?? false
  }

  private static func isConvertibleToGuard(_ ifExpr: IfExprSyntax) -> Bool {
    guard ifExpr.elseBody == nil else {
      return false
    }

    for condition in ifExpr.conditions {
      if let optionalBinding = condition.condition.as(OptionalBindingConditionSyntax.self) {
        if optionalBinding.pattern.is(ExpressionPatternSyntax.self) {
          return false
        }
      } else if condition.condition.is(MatchingPatternConditionSyntax.self) {
        return false
      }
    }

    // Changing if-let to guard would change the lifetime of deferred blocks.
    if ifExpr.body.statements.contains(where: { $0.item.is(DeferStmtSyntax.self) }) {
      return false
    }

    return bodyGuaranteesExit(ifExpr.body)
  }

  private static func bodyGuaranteesExit(_ codeBlock: CodeBlockSyntax) -> Bool {
    return codeBlock.statements.reversed().contains { statementGuaranteesExit($0.item) }
  }

  /// Checks if a statement guarantees control flow will not continue past it.
  ///
  /// - Note: Does not attempt to detect never-returning functions like `fatalError`
  ///   because that requires semantic information (return type `Never`).
  /// - Note: Switch statements are conservatively treated as non-exiting since
  ///   checking exhaustiveness is complex.
  private static func statementGuaranteesExit(_ statement: CodeBlockItemSyntax.Item) -> Bool {
    switch statement {
    case .stmt(let stmt):
      switch stmt.kind {
      case .returnStmt, .throwStmt, .breakStmt, .continueStmt:
        return true
      default:
        if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
          return statementGuaranteesExit(.expr(exprStmt.expression))
        }
      }

    case .expr(let expr):
      if let ifExpr = expr.as(IfExprSyntax.self), let elseBody = ifExpr.elseBody {
        guard bodyGuaranteesExit(ifExpr.body) else {
          return false
        }
        switch elseBody {
        case .codeBlock(let block):
          return bodyGuaranteesExit(block)
        case .ifExpr(let elseIf):
          return statementGuaranteesExit(CodeBlockItemSyntax.Item(elseIf))
        }
      }

    case .decl:
      break
    }

    return false
  }

  private static func buildGuardStatement(
    from ifExpr: IfExprSyntax,
    elseBody: [CodeBlockItemSyntax],
    baseIndentation: Trivia,
    indentStep: Trivia
  ) -> GuardStmtSyntax {
    var elseStatementsList = elseBody.enumerated().map { index, stmt in
      return stmt.indented(by: indentStep)
    }

    if var lastStmt = elseStatementsList.last,
      lastStmt.trailingTrivia.pieces.last?.isNewline ?? false
    {
      lastStmt.trailingTrivia = Trivia(pieces: lastStmt.trailingTrivia.pieces.dropLast())
      elseStatementsList[elseStatementsList.count - 1] = lastStmt
    }

    let elseBlock = CodeBlockSyntax(
      leftBrace: .leftBraceToken(),
      statements: CodeBlockItemListSyntax(elseStatementsList),
      rightBrace: .rightBraceToken(leadingTrivia: .newline + baseIndentation)
    )

    return GuardStmtSyntax(
      guardKeyword: .keyword(.guard, trailingTrivia: .space),
      conditions: normalizeConditionsTrivia(ifExpr.conditions),
      elseKeyword: .keyword(.else, leadingTrivia: .space, trailingTrivia: .space),
      body: elseBlock
    )
  }

  /// Normalize conditions trivia by stripping trailing whitespace from the end of the last condition.
  /// This prevents double spaces before the `else` keyword while preserving spaces before comments.
  private static func normalizeConditionsTrivia(
    _ conditions: ConditionElementListSyntax
  ) -> ConditionElementListSyntax {
    guard var lastCondition = conditions.last else {
      return conditions
    }

    let trimmedPieces = lastCondition.trailingTrivia.droppingLast(while: \.isSpaceOrTab)

    lastCondition.trailingTrivia = Trivia(pieces: Array(trimmedPieces))
    var newConditions = Array(conditions.dropLast())
    newConditions.append(lastCondition)
    return ConditionElementListSyntax(newConditions)
  }
}

private func isFunctionBoundary(_ syntax: Syntax) -> Bool {
  [.functionDecl, .initializerDecl, .accessorDecl, .subscriptDecl, .closureExpr].contains(syntax.kind)
}
