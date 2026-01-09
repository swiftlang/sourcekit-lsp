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

    // Get statements following the if statement
    guard let ifIndex = codeBlockItemList.index(of: codeBlockItem) else {
      return []
    }

    let followingStatements = codeBlockItemList[codeBlockItemList.index(after: ifIndex)...]
    guard let lastStatement = followingStatements.last else {
      return []
    }

    // Get indentation info
    let baseIndentation = ifExpr.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    let indentStep =
      BasicFormat.inferIndentation(of: ifExpr.body)
      ?? inferIndentStep(from: ifExpr.body, baseIndentation: baseIndentation)

    let guardStmt = buildGuardStatement(
      from: ifExpr,
      elseBody: Array(followingStatements),
      baseIndentation: baseIndentation,
      indentStep: indentStep
    )
    let newBodyStatements = ifExpr.body.statements

    let rangeStart = ifExpr.positionAfterSkippingLeadingTrivia
    let rangeEnd = lastStatement.endPosition

    var replacementText = guardStmt.description

    // Use SyntaxRewriter to safely adjust indentation
    let adjuster = IndentationAdjuster(remove: indentStep)
    for stmt in newBodyStatements {
      // Ensure the statement starts on a new line with base indentation
      // We first adjust internal indentation, then force the leading trivia
      let adjustedStmt = adjuster.rewrite(stmt)
      let finalStmt = adjustedStmt.with(\.leadingTrivia, .newline + baseIndentation)
      replacementText += finalStmt.description
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
    let ifExpr = scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IfExprSyntax.self,
      stoppingIf: isFunctionBoundary
    )
    guard let ifExpr, isConvertibleToGuard(ifExpr) else {
      return nil
    }
    return ifExpr
  }

  /// Checks if an if expression can be converted to a guard statement.
  ///
  /// Returns `false` for:
  /// - If statements with an else clause
  /// - `if case let` patterns (matching patterns not supported)
  /// - Bodies containing `defer` (would change defer lifetime semantics)
  /// - Bodies that don't guarantee an early exit
  private static func isConvertibleToGuard(_ ifExpr: IfExprSyntax) -> Bool {
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
        // Check if this is an ExpressionStmtSyntax containing an if-else
        if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
          return statementGuaranteesExit(.expr(exprStmt.expression))
        }
      }

    case .expr(let expr):
      // Check for if-else where both branches exit
      if let ifExpr = expr.as(IfExprSyntax.self),
        let elseBody = ifExpr.elseBody
      {
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

      // Switch expressions are treated as non-exiting since determining exhaustiveness
      // requires semantic analysis (e.g., knowing all enum cases).
      if expr.is(SwitchExprSyntax.self) {
        return false
      }

    case .decl:
      break
    }

    return false
  }

  /// Builds a guard statement from an if expression.
  private static func buildGuardStatement(
    from ifExpr: IfExprSyntax,
    elseBody: [CodeBlockItemSyntax],
    baseIndentation: Trivia,
    indentStep: Trivia
  ) -> GuardStmtSyntax {
    let innerIndentation = baseIndentation + indentStep

    // Build else body statements with proper indentation
    let elseStatements = CodeBlockItemListSyntax(
      elseBody.enumerated().map { index, stmt in
        let leadingTrivia: Trivia = index == 0 ? innerIndentation : .newline + innerIndentation
        return stmt.with(\.leadingTrivia, leadingTrivia)
      }
    )

    let elseBlock = CodeBlockSyntax(
      leftBrace: .leftBraceToken(trailingTrivia: .newline),
      statements: elseStatements,
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
  private static func normalizeConditionsTrivia(_ conditions: ConditionElementListSyntax) -> ConditionElementListSyntax
  {
    guard var lastCondition = conditions.last else {
      return conditions
    }

    // Strip trailing spaces/tabs only from the END of the trivia
    // E.g., [space, blockComment, space] -> [space, blockComment]
    var pieces = Array(lastCondition.trailingTrivia)
    while let last = pieces.last {
      switch last {
      case .spaces, .tabs:
        pieces.removeLast()
      default:
        break
      }
      // Exit loop once we've hit non-whitespace
      if case .spaces = last { continue }
      if case .tabs = last { continue }
      break
    }

    lastCondition = lastCondition.with(\.trailingTrivia, Trivia(pieces: pieces))

    // Rebuild conditions list with normalized last element
    var newConditions = Array(conditions.dropLast())
    newConditions.append(lastCondition)
    return ConditionElementListSyntax(newConditions)
  }
}

/// Check if the given syntax node represents a function-level boundary
/// (function, initializer, accessor, subscript, or closure).
private func isFunctionBoundary(_ syntax: Syntax) -> Bool {
  [.functionDecl, .initializerDecl, .accessorDecl, .subscriptDecl, .closureExpr].contains(syntax.kind)
}

/// Fallback inference of indent step when BasicFormat.inferIndentation returns nil.
private func inferIndentStep(from codeBlock: CodeBlockSyntax, baseIndentation: Trivia) -> Trivia {
  guard let firstStmt = codeBlock.statements.first else {
    return .spaces(2)
  }

  let stmtIndentation = firstStmt.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
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
      return .tabs(stmtCount / 8 - baseTabs)
    }
    return .spaces(diff)
  }

  return .spaces(2)
}

/// SyntaxRewriter that reduces indentation by a specified amount for lines starting with a newline.
private class IndentationAdjuster: SyntaxRewriter {
  let indentToRemove: Trivia

  init(remove indent: Trivia) {
    self.indentToRemove = indent
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ token: TokenSyntax) -> TokenSyntax {
    var pieces = Array(token.leadingTrivia)

    // Find the last newline in the trivia
    guard let lastNewlineIndex = pieces.lastIndex(where: { $0.isNewline }) else {
      return token
    }

    // The indentation follows the last newline
    let indentationPieces = pieces[(lastNewlineIndex + 1)...]
    let searchIndex = indentationPieces.startIndex
    var removeIndex = 0

    // Check if the indentation starts with the indentToRemove
    let pattern = indentToRemove.pieces
    var matched = true

    // Simple matching: check if pieces match
    // Note: This matches exact pieces (e.g. .spaces(4) matches .spaces(4))
    // Logic could be improved to handle splitted spaces (e.g. remove 2 from 4) if needed,
    // but typically IndentationInferrer returns consistent units.
    for patternPiece in pattern {
      if removeIndex >= indentationPieces.count {
        matched = false
        break
      }
      let currentPiece = indentationPieces[searchIndex + removeIndex]

      if currentPiece == patternPiece {
        removeIndex += 1
        continue
      }

      // Handle case where we remove 2 spaces from 4 spaces
      if case .spaces(let currentN) = currentPiece, case .spaces(let patternN) = patternPiece, currentN >= patternN {
        // Modify the piece in place to subtract
        pieces[lastNewlineIndex + 1 + removeIndex] = .spaces(currentN - patternN)
        // We successfully consumed the pattern "logically", but we modified the stream
        // so we don't need to remove subsequent pieces for this pattern piece.
        // However, we need to match the rest of the pattern?
        // Usually indentStep is just spaces(2) or spaces(4) or tabs(1).
        // So a single piece match is common.
        matched = true
        break
      }
      if case .tabs(let currentN) = currentPiece, case .tabs(let patternN) = patternPiece, currentN >= patternN {
        pieces[lastNewlineIndex + 1 + removeIndex] = .tabs(currentN - patternN)
        matched = true
        break
      }

      matched = false
      break
    }

    if matched {
      // If we matched exact pieces, remove them.
      // If we matched by subtraction (break case above), we modified 'pieces' already
      // and don't need to remove indices, just filtered out empty pieces?

      // Simplified logic assuming common case of exact match or simple subtraction of one piece
      if removeIndex > 0 {
        pieces.removeSubrange((lastNewlineIndex + 1)..<(lastNewlineIndex + 1 + removeIndex))
      }
    }

    return token.with(\.leadingTrivia, Trivia(pieces: pieces))
  }
}
