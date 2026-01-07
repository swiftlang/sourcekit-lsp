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
@_spi(Testing) public import SwiftSyntax
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

    // ifExpr might be in a CodeBlockItem directly, or wrapped in an ExpressionStmt
    let codeBlockItem: CodeBlockItemSyntax
    if let parent = ifExpr.parent?.as(CodeBlockItemSyntax.self) {
      codeBlockItem = parent
    } else if let exprStmt = ifExpr.parent?.as(ExpressionStmtSyntax.self),
      let parent = exprStmt.parent?.as(CodeBlockItemSyntax.self)
    {
      codeBlockItem = parent
    } else {
      return []
    }

    guard let codeBlockItemList = codeBlockItem.parent?.as(CodeBlockItemListSyntax.self) else {
      return []
    }

    // Get statements following the if statement
    guard let ifIndex = codeBlockItemList.index(of: codeBlockItem) else {
      return []
    }

    let followingStatements = codeBlockItemList[codeBlockItemList.index(after: ifIndex)...]
    guard !followingStatements.isEmpty else {
      return []
    }

    let guardStmt = buildGuardStatement(from: ifExpr, elseBody: Array(followingStatements))
    let newBodyStatements = ifExpr.body.statements

    let lastStatement = followingStatements[followingStatements.index(before: followingStatements.endIndex)]
    let rangeStart = ifExpr.positionAfterSkippingLeadingTrivia
    let rangeEnd = lastStatement.endPosition

    var replacementText = guardStmt.description
    let baseIndentation = ifExpr.leadingTrivia.indentation ?? []
    for stmt in newBodyStatements {
      let newTrivia: Trivia = .newline + baseIndentation
      let unindentedStmt = stmt.with(\.leadingTrivia, newTrivia)
      replacementText += unindentedStmt.description
    }

    let edit = TextEdit(
      range: scope.snapshot.absolutePositionRange(of: rangeStart..<rangeEnd),
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

  /// Find an if expression that can be converted to guard.
  /// Requirements:
  /// - Must be an `if let` or `if var` (optional binding conditions only, no `case let`)
  /// - No else clause
  /// - Body must end with an early exit (return/throw/break/continue)
  /// - Must not contain defer statements
  /// - Body must guarantee exit (all code paths must exit)
  private static func findConvertibleIfExpr(in scope: SyntaxCodeActionScope) -> IfExprSyntax? {
    guard let node = scope.innermostNodeContainingRange else {
      return nil
    }

    var current: Syntax? = node
    while let syntax = current {
      if let ifExpr = syntax.as(IfExprSyntax.self) {
        if isConvertibleToGuard(ifExpr) {
          return ifExpr
        }
      }

      if isFunctionBoundary(syntax) {
        break
      }

      current = syntax.parent
    }
    return nil
  }

  /// Checks if an if expression can be converted to a guard statement.
  ///
  /// Returns `false` for:
  /// - If statements with an else clause
  /// - `if case let` patterns (matching patterns not supported)
  /// - Bodies containing `defer` (would change defer lifetime semantics)
  /// - Bodies that don't guarantee an early exit
  @_spi(Testing)
  public static func isConvertibleToGuard(_ ifExpr: IfExprSyntax) -> Bool {
    guard ifExpr.elseKeyword == nil, ifExpr.elseBody == nil else {
      return false
    }

    for condition in ifExpr.conditions {
      guard let optionalBinding = condition.condition.as(OptionalBindingConditionSyntax.self) else {
        if condition.condition.is(MatchingPatternConditionSyntax.self) {
          return false
        }
        continue
      }
      if optionalBinding.pattern.is(ExpressionPatternSyntax.self) {
        return false
      }
    }

    if ifExpr.body.statements.contains(where: { $0.item.is(DeferStmtSyntax.self) }) {
      return false
    }

    return bodyGuaranteesExit(ifExpr.body)
  }

  /// Check if the code block guarantees an early exit on all paths.
  private static func bodyGuaranteesExit(_ codeBlock: CodeBlockSyntax) -> Bool {
    guard let lastStatement = codeBlock.statements.last else {
      return false
    }

    return statementGuaranteesExit(lastStatement.item)
  }

  /// Checks if a statement guarantees control flow will not continue past it.
  ///
  /// Recognizes direct exit statements (`return`, `throw`, `break`, `continue`)
  /// and if-else chains where both branches exit.
  ///
  /// - Note: Does not attempt to detect never-returning functions like `fatalError`
  ///   because that requires type information to verify the return type is `Never`.
  /// - Note: Switch statements are conservatively treated as non-exiting since
  ///   checking all cases for guaranteed exit is complex.
  private static func statementGuaranteesExit(_ statement: CodeBlockItemSyntax.Item) -> Bool {
    switch statement {
    case .stmt(let stmt):
      switch stmt.kind {
      case .returnStmt, .throwStmt, .breakStmt, .continueStmt:
        return true
      default:
        break
      }

    case .expr(let expr):
      // Check for if-else where both branches exit
      if let ifExpr = expr.as(IfExprSyntax.self),
        ifExpr.elseKeyword != nil,
        let elseBody = ifExpr.elseBody
      {
        let thenExits = bodyGuaranteesExit(ifExpr.body)
        let elseExits: Bool
        switch elseBody {
        case .codeBlock(let block):
          elseExits = bodyGuaranteesExit(block)
        case .ifExpr(let elseIf):
          elseExits = statementGuaranteesExit(CodeBlockItemSyntax.Item(elseIf))
        }
        return thenExits && elseExits
      }

      // Check for switch expressions
      // TODO: Implement proper switch exhaustiveness checking.
      // A full implementation would verify all cases contain exit statements.
      // For now, conservatively return false to avoid incorrect transformations.
      if expr.is(SwitchExprSyntax.self) {
        return false
      }

    case .decl:
      break
    }

    return false
  }

  /// Builds a guard statement from an if expression.
  /// Infers indentation from the if body's existing indentation.
  private static func buildGuardStatement(
    from ifExpr: IfExprSyntax,
    elseBody: [CodeBlockItemSyntax]
  ) -> GuardStmtSyntax {
    let baseIndentation = ifExpr.leadingTrivia.indentation ?? []
    let indentStep = inferIndentStep(from: ifExpr.body, baseIndentation: baseIndentation)
    let innerIndentation = baseIndentation + indentStep

    let elseStatements = applyIndentation(to: elseBody, indentation: innerIndentation)

    let elseBlock = CodeBlockSyntax(
      leftBrace: .leftBraceToken(trailingTrivia: .newline),
      statements: elseStatements,
      rightBrace: .rightBraceToken(leadingTrivia: .newline + baseIndentation)
    )

    return GuardStmtSyntax(
      guardKeyword: .keyword(.guard, trailingTrivia: .space),
      conditions: ifExpr.conditions,
      elseKeyword: .keyword(.else, leadingTrivia: .space, trailingTrivia: .space),
      body: elseBlock
    )
  }
}

@_spi(Testing) public struct ConvertGuardToIfLet: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let guardStmt = findConvertibleGuardStmt(in: scope) else {
      return []
    }

    guard let codeBlockItem = guardStmt.parent?.as(CodeBlockItemSyntax.self),
      let codeBlockItemList = codeBlockItem.parent?.as(CodeBlockItemListSyntax.self)
    else {
      return []
    }

    guard let guardIndex = codeBlockItemList.index(of: codeBlockItem) else {
      return []
    }

    let followingStatements = codeBlockItemList[codeBlockItemList.index(after: guardIndex)...]
    guard !followingStatements.isEmpty else {
      return []
    }

    let ifExpr = buildIfExpression(from: guardStmt, thenBody: Array(followingStatements))
    let elseStatements = guardStmt.body.statements

    let lastStatement = followingStatements[followingStatements.index(before: followingStatements.endIndex)]
    let rangeStart = guardStmt.positionAfterSkippingLeadingTrivia
    let rangeEnd = lastStatement.endPosition

    var replacementText = ifExpr.description

    // Statements from guard body move to outer scope, so unindent them
    let baseIndentation = guardStmt.leadingTrivia.indentation ?? []
    let stmtArray = Array(elseStatements)

    for (index, stmt) in stmtArray.enumerated() {
      let newTrivia: Trivia = .newline + baseIndentation
      var unindentedStmt = stmt.with(\.leadingTrivia, newTrivia)
      // Strip only trailing whitespace (not comments) from the last statement
      if index == stmtArray.count - 1 {
        unindentedStmt = unindentedStmt.with(\.trailingTrivia, stmt.trailingTrivia.trimmingTrailingWhitespace)
      }
      replacementText += unindentedStmt.description
    }

    let edit = TextEdit(
      range: scope.snapshot.absolutePositionRange(of: rangeStart..<rangeEnd),
      newText: replacementText
    )

    return [
      CodeAction(
        title: "Convert to if",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  private static func findConvertibleGuardStmt(in scope: SyntaxCodeActionScope) -> GuardStmtSyntax? {
    guard let node = scope.innermostNodeContainingRange else {
      return nil
    }

    var current: Syntax? = node
    while let syntax = current {
      if let guardStmt = syntax.as(GuardStmtSyntax.self) {
        if isConvertibleToIfLet(guardStmt) {
          return guardStmt
        }
      }

      if isFunctionBoundary(syntax) {
        break
      }

      current = syntax.parent
    }
    return nil
  }

  /// Checks if a guard statement can be converted to an if-let.
  ///
  /// Returns `false` for:
  /// - `guard case let` patterns (matching patterns not supported)
  /// - Guard bodies containing `defer` (would change defer lifetime semantics)
  ///
  /// - Note: Does not check for following statements; that's done in `codeActions()`.
  @_spi(Testing)
  public static func isConvertibleToIfLet(_ guardStmt: GuardStmtSyntax) -> Bool {
    for condition in guardStmt.conditions {
      if let optionalBinding = condition.condition.as(OptionalBindingConditionSyntax.self) {
        if optionalBinding.pattern.is(ExpressionPatternSyntax.self) {
          return false
        }
      } else if condition.condition.is(MatchingPatternConditionSyntax.self) {
        return false
      }
    }

    if guardStmt.body.statements.contains(where: { $0.item.is(DeferStmtSyntax.self) }) {
      return false
    }

    return true
  }

  /// Builds an if expression from a guard statement.
  /// Infers indentation from the guard body's existing indentation.
  private static func buildIfExpression(
    from guardStmt: GuardStmtSyntax,
    thenBody: [CodeBlockItemSyntax]
  ) -> IfExprSyntax {
    let baseIndentation = guardStmt.leadingTrivia.indentation ?? []
    let indentStep = inferIndentStep(from: guardStmt.body, baseIndentation: baseIndentation)
    let innerIndentation = baseIndentation + indentStep

    let bodyStatements = applyIndentation(to: thenBody, indentation: innerIndentation)

    let body = CodeBlockSyntax(
      leftBrace: .leftBraceToken(trailingTrivia: .newline),
      statements: bodyStatements,
      rightBrace: .rightBraceToken(leadingTrivia: .newline + baseIndentation)
    )

    return IfExprSyntax(
      ifKeyword: .keyword(.if, trailingTrivia: .space),
      conditions: guardStmt.conditions,
      body: body
    )
  }
}

/// Check if the given syntax node represents a function-level boundary
/// (function, initializer, accessor, or closure).
private func isFunctionBoundary(_ syntax: Syntax) -> Bool {
  syntax.is(FunctionDeclSyntax.self) || syntax.is(InitializerDeclSyntax.self) || syntax.is(AccessorDeclSyntax.self)
    || syntax.is(ClosureExprSyntax.self)
}

/// Apply indentation to a list of statements, with the first statement
/// getting just indentation and subsequent statements getting newline + indentation.
private func applyIndentation(
  to statements: [CodeBlockItemSyntax],
  indentation: Trivia
) -> CodeBlockItemListSyntax {
  CodeBlockItemListSyntax(
    statements.enumerated().map { index, stmt in
      stmt.with(\.leadingTrivia, index == 0 ? indentation : .newline + indentation)
    }
  )
}

/// Infer the indentation step used in a code block by comparing
/// the first statement's indentation to the base indentation.
/// Falls back to 2 spaces if indentation cannot be determined.
private func inferIndentStep(from codeBlock: CodeBlockSyntax, baseIndentation: Trivia) -> Trivia {
  guard let firstStmt = codeBlock.statements.first else {
    return .spaces(2)
  }

  let stmtIndentation = firstStmt.leadingTrivia.indentation ?? []
  let baseCount = baseIndentation.sourceLength.utf8Length
  let stmtCount = stmtIndentation.sourceLength.utf8Length

  if stmtCount > baseCount {
    let diff = stmtCount - baseCount
    // Preserve the type of whitespace (spaces vs tabs) from the statement
    if case .tabs(let n) = stmtIndentation.pieces.first, n > 0 {
      let baseTabs =
        baseIndentation.pieces.first.map { piece -> Int in
          if case .tabs(let t) = piece { return t }
          return 0
        } ?? 0
      return .tabs(stmtCount / 8 - baseTabs)  // Rough estimate for tabs
    }
    return .spaces(diff)
  }

  return .spaces(2)
}

private extension Trivia {
  /// Extract the indentation from trivia (spaces and tabs at the end).
  var indentation: Trivia? {
    var pieces: [TriviaPiece] = []
    for piece in reversed() {
      switch piece {
      case .spaces, .tabs:
        pieces.insert(piece, at: 0)
      case .newlines:
        break
      default:
        pieces.removeAll()
      }
    }
    return pieces.isEmpty ? nil : Trivia(pieces: pieces)
  }

  /// Remove trailing spaces and tabs, preserving comments and other trivia.
  var trimmingTrailingWhitespace: Trivia {
    var pieces = self.pieces
    while let last = pieces.last {
      switch last {
      case .spaces, .tabs:
        pieces.removeLast()
      default:
        return Trivia(pieces: pieces)
      }
    }
    return Trivia(pieces: pieces)
  }
}
