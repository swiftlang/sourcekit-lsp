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

    let guardStmt = buildGuardStatement(from: ifExpr, elseBody: Array(followingStatements))
    let newBodyStatements = ifExpr.body.statements

    let rangeStart = ifExpr.positionAfterSkippingLeadingTrivia
    let rangeEnd = lastStatement.endPosition

    var replacementText = guardStmt.description
    let baseIndentation = ifExpr.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    // Infer the inner block's indentation from the first statement
    let innerIndentation =
      newBodyStatements.first?.firstToken(viewMode: .sourceAccurate)?.indentationOfLine
      ?? (baseIndentation + .spaces(2))
    for stmt in newBodyStatements {
      replacementText += adjustingIndentation(of: stmt, from: innerIndentation, to: baseIndentation)
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
  /// Infers indentation from the if body's existing indentation.
  private static func buildGuardStatement(
    from ifExpr: IfExprSyntax,
    elseBody: [CodeBlockItemSyntax]
  ) -> GuardStmtSyntax {
    let baseIndentation = ifExpr.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
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
      return .tabs(stmtCount / 8 - baseTabs)  // Rough estimate for tabs
    }
    return .spaces(diff)
  }

  return .spaces(2)
}

/// Adjusts indentation of a statement by replacing occurrences of `oldIndent`
/// with `newIndent` after each newline. This preserves comments and other non-whitespace
/// trivia while properly unindenting all lines (including multi-line statements).
///
/// - Parameters:
///   - stmt: The statement to adjust indentation for
///   - oldIndent: The indentation to replace (typically the inner block's indentation)
///   - newIndent: The new indentation to use (typically the outer scope's indentation)
/// - Returns: The statement's description with adjusted indentation, with leading newline
private func adjustingIndentation(
  of stmt: CodeBlockItemSyntax,
  from oldIndent: Trivia,
  to newIndent: Trivia
) -> String {
  let oldIndentStr = oldIndent.description
  let newIndentStr = newIndent.description

  var result = stmt.description

  // Replace all occurrences of \n<oldIndent> with \n<newIndent>
  // This handles both leading trivia newlines and internal newlines in multi-line statements
  if !oldIndentStr.isEmpty {
    result = result.replacingOccurrences(of: "\n" + oldIndentStr, with: "\n" + newIndentStr)
  }

  // Handle first line indentation
  if result.hasPrefix(oldIndentStr) && !oldIndentStr.isEmpty {
    // Standard case: replace old indentation with new
    result = newIndentStr + String(result.dropFirst(oldIndentStr.count))
  } else if !result.hasPrefix("\n") {
    // Single-line block case: strip any leading whitespace and use new indentation
    // This handles cases like `{ return nil }` where statement has minimal leading trivia
    var trimmed = result
    while trimmed.hasPrefix(" ") || trimmed.hasPrefix("\t") {
      trimmed.removeFirst()
    }
    result = newIndentStr + trimmed
  }

  // Ensure result starts with newline for proper statement separation
  if !result.hasPrefix("\n") {
    result = "\n" + result
  }

  return result
}
