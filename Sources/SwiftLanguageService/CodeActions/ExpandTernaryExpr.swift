//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftBasicFormat
import SwiftOperators
import SwiftSyntax
import SwiftSyntaxBuilder

/// Syntactic code action provider to expand a ternary conditional expression
/// into an if-else expression or statement.
///
/// ## Before
/// ```swift
/// let x = condition ? trueValue : falseValue
/// ```
///
/// ## After
/// ```swift
/// let x = if condition {
///     trueValue
/// } else {
///     falseValue
/// }
/// ```
///
/// When the ternary is within a return statement, it expands to an if-else statement:
///
/// ## Before
/// ```swift
/// return condition ? a : b
/// ```
///
/// ## After
/// ```swift
/// if condition {
///     return a
/// } else {
///     return b
/// }
/// ```
@_spi(Testing) public struct ExpandTernaryExprCodeAction: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    // First try to find a SequenceExprSyntax that might contain a ternary
    var seqExpr: SequenceExprSyntax?
    var returnStmt: ReturnStmtSyntax?

    // Check if we're at a return statement - if so, look at its expression
    if let stmt = node.findParentOfSelf(
      ofType: ReturnStmtSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    ) {
      returnStmt = stmt
      seqExpr = stmt.expression?.as(SequenceExprSyntax.self)
    }

    // If not found via return statement, look for SequenceExprSyntax directly
    if seqExpr == nil {
      seqExpr = node.findParentOfSelf(
        ofType: SequenceExprSyntax.self,
        stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
      )
      // Check if this sequence expression is inside a return statement
      if let seq = seqExpr, returnStmt == nil {
        returnStmt = seq.parent?.as(ReturnStmtSyntax.self)
      }
    }

    guard let seqExpr else {
      return []
    }

    // Fold the sequence expression to get proper operator structure
    guard let foldedExpr = OperatorTable.standardOperators.foldAll(
      ExprSyntax(seqExpr),
      errorHandler: { _ in }
    ).as(ExprSyntax.self) else {
      return []
    }

    // Find the ternary expression in the folded result
    guard let ternary = foldedExpr.as(TernaryExprSyntax.self) else {
      return []
    }

    // Check if ternary is in a return statement
    if let returnStmt {
      return expandReturnTernary(ternary, in: returnStmt, originalSeqExpr: seqExpr, scope: scope)
    }

    // Default: just expand ternary to if-expression
    return expandTernaryToIfExpr(ternary, originalSeqExpr: seqExpr, scope: scope)
  }

  private static func expandTernaryToIfExpr(
    _ ternary: TernaryExprSyntax,
    originalSeqExpr: SequenceExprSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    let condition = ternary.condition
      .with(\.leadingTrivia, [])
      .with(\.trailingTrivia, [])
    let thenExpr = ternary.thenExpression
      .with(\.leadingTrivia, [])
      .with(\.trailingTrivia, [])
    let elseExpr = ternary.elseExpression
      .with(\.leadingTrivia, [])
      .with(\.trailingTrivia, [])

    // Use original sequence expression for indentation since folded tree doesn't have valid positions
    let baseIndentation = originalSeqExpr.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    let indentStep = BasicFormat.inferIndentation(of: originalSeqExpr.root) ?? .spaces(4)

    // Build the if-expression
    let ifExpr = IfExprSyntax(
      ifKeyword: .keyword(.if, trailingTrivia: .space),
      conditions: ConditionElementListSyntax {
        ConditionElementSyntax(condition: .expression(ExprSyntax(condition)))
      },
      body: CodeBlockSyntax(
        leftBrace: .leftBraceToken(leadingTrivia: .space),
        statements: CodeBlockItemListSyntax {
          CodeBlockItemSyntax(
            leadingTrivia: .newline + baseIndentation + indentStep,
            item: .expr(thenExpr)
          )
        },
        rightBrace: .rightBraceToken(leadingTrivia: .newline + baseIndentation)
      ),
      elseKeyword: .keyword(.else, leadingTrivia: .space, trailingTrivia: .space),
      elseBody: .codeBlock(
        CodeBlockSyntax(
          statements: CodeBlockItemListSyntax {
            CodeBlockItemSyntax(
              leadingTrivia: .newline + baseIndentation + indentStep,
              item: .expr(elseExpr)
            )
          },
          rightBrace: .rightBraceToken(leadingTrivia: .newline + baseIndentation)
        )
      )
    )

    // Use original sequence expression for edit range
    let edit = TextEdit(
      range: scope.snapshot.absolutePositionRange(
        of: originalSeqExpr.positionAfterSkippingLeadingTrivia..<originalSeqExpr.endPositionBeforeTrailingTrivia
      ),
      newText: ifExpr.description
    )

    return [
      CodeAction(
        title: "Expand ternary expression",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  private static func expandReturnTernary(
    _ ternary: TernaryExprSyntax,
    in returnStmt: ReturnStmtSyntax,
    originalSeqExpr: SequenceExprSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    let condition = ternary.condition
      .with(\.leadingTrivia, [])
      .with(\.trailingTrivia, [])
    let thenExpr = ternary.thenExpression
      .with(\.leadingTrivia, [])
      .with(\.trailingTrivia, [])
    let elseExpr = ternary.elseExpression
      .with(\.leadingTrivia, [])
      .with(\.trailingTrivia, [])

    // Use original syntax for indentation
    let baseIndentation = returnStmt.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    let indentStep = BasicFormat.inferIndentation(of: originalSeqExpr.root) ?? .spaces(4)

    // Build: if condition { return a } else { return b }
    let ifExpr = IfExprSyntax(
      ifKeyword: .keyword(.if, trailingTrivia: .space),
      conditions: ConditionElementListSyntax {
        ConditionElementSyntax(condition: .expression(ExprSyntax(condition)))
      },
      body: CodeBlockSyntax(
        leftBrace: .leftBraceToken(leadingTrivia: .space),
        statements: CodeBlockItemListSyntax {
          CodeBlockItemSyntax(
            leadingTrivia: .newline + baseIndentation + indentStep,
            item: .stmt(
              StmtSyntax(
                ReturnStmtSyntax(
                  returnKeyword: .keyword(.return, trailingTrivia: .space),
                  expression: thenExpr
                )
              )
            )
          )
        },
        rightBrace: .rightBraceToken(leadingTrivia: .newline + baseIndentation)
      ),
      elseKeyword: .keyword(.else, leadingTrivia: .space, trailingTrivia: .space),
      elseBody: .codeBlock(
        CodeBlockSyntax(
          statements: CodeBlockItemListSyntax {
            CodeBlockItemSyntax(
              leadingTrivia: .newline + baseIndentation + indentStep,
              item: .stmt(
                StmtSyntax(
                  ReturnStmtSyntax(
                    returnKeyword: .keyword(.return, trailingTrivia: .space),
                    expression: elseExpr
                  )
                )
              )
            )
          },
          rightBrace: .rightBraceToken(leadingTrivia: .newline + baseIndentation)
        )
      )
    )

    let edit = TextEdit(
      range: scope.snapshot.absolutePositionRange(
        of: returnStmt.positionAfterSkippingLeadingTrivia..<returnStmt.endPositionBeforeTrailingTrivia
      ),
      newText: ifExpr.description
    )

    return [
      CodeAction(
        title: "Expand ternary expression",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }
}
