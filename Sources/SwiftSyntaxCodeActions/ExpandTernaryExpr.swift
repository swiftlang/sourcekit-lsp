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

import SwiftBasicFormat
import SwiftOperators
import SwiftRefactor
package import SwiftSyntax

/// Converts a ternary conditional expression to an `if` expression.
///
/// ## Before
///
/// ```swift
/// let x = condition ? trueValue : falseValue
/// ```
///
/// ## After
///
/// ```swift
/// let x = if condition {
///   trueValue
/// } else {
///   falseValue
/// }
/// ```
///
/// The refactoring is only offered where `if` can be used as an expression: as a statement, in a variable
/// initializer, as the source of an assignment, and after `return` or `throw`.
package struct ExpandTernaryExpr: SyntaxRefactoringProvider, SyntaxRefactoringCodeActionProvider {
  package static let title: String = "Expand Ternary Expression"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> ExprSyntax? {
    var node = scope.innermostNodeContainingRange
    while let current = node, !current.is(CodeBlockItemSyntax.self), !current.is(MemberBlockItemSyntax.self) {
      if let candidate = candidateExpression(for: current), (try? refactor(syntax: candidate)) != nil {
        return candidate
      }
      node = current.parent
    }
    return nil
  }

  /// The expression that should be expanded if the code action is requested on `node`.
  private static func candidateExpression(for node: Syntax) -> ExprSyntax? {
    if let expr = node.as(ExprSyntax.self), canBeIfExpression(expr) {
      return expr
    }
    // Also offer the refactoring when the cursor is on the `let` keyword or the variable name.
    if let binding = node.as(PatternBindingSyntax.self) {
      return binding.initializer?.value
    }
    if let variableDecl = node.as(VariableDeclSyntax.self), variableDecl.bindings.count == 1 {
      return variableDecl.bindings.first?.initializer?.value
    }
    return nil
  }

  /// Whether `expr` is at a position where `if` can be used as an expression.
  private static func canBeIfExpression(_ expr: ExprSyntax) -> Bool {
    guard let parent = expr.parent else {
      return false
    }
    if parent.is(CodeBlockItemSyntax.self) || parent.is(ReturnStmtSyntax.self) || parent.is(ThrowStmtSyntax.self) {
      return true
    }
    // Initializer clauses are also used for default arguments, which can't be `if` expressions.
    if let initializer = parent.as(InitializerClauseSyntax.self) {
      return initializer.parent?.is(PatternBindingSyntax.self) ?? false
        || initializer.parent?.is(OptionalBindingConditionSyntax.self) ?? false
    }
    return false
  }

  package static func refactor(syntax: ExprSyntax, in context: Void = ()) throws -> ExprSyntax {
    let indentation = Indentation(
      base: syntax.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? [],
      step: BasicFormat.inferIndentation(of: syntax.root) ?? .spaces(4)
    )

    // The parser doesn't apply operator precedence, so fold the expression to find the ternary expression.
    var expr = syntax
    if let sequence = syntax.as(SequenceExprSyntax.self) {
      guard let folded = try? OperatorTable.standardOperators.foldSingle(sequence) else {
        throw RefactoringNotApplicableError("failed to fold operators")
      }
      expr = folded
    }

    if let ternary = expr.as(TernaryExprSyntax.self) {
      return ExprSyntax(ifExpr(from: ternary, indentation: indentation))
    }
    if let assignment = expr.as(InfixOperatorExprSyntax.self), assignment.operator.is(AssignmentExprSyntax.self),
      let ternary = assignment.rightOperand.as(TernaryExprSyntax.self)
    {
      return ExprSyntax(assignment.with(\.rightOperand, ExprSyntax(ifExpr(from: ternary, indentation: indentation))))
    }
    throw RefactoringNotApplicableError("not a ternary expression")
  }

  private struct Indentation {
    /// The indentation of the line that the ternary expression starts on.
    let base: Trivia
    /// One level of indentation, used for the bodies of the `if` expression.
    let step: Trivia
  }

  private static func ifExpr(from ternary: TernaryExprSyntax, indentation: Indentation) -> IfExprSyntax {
    let bodyIndentation = indentation.base + indentation.step

    // Remove the whitespace around the condition and the branches but keep the comments.
    let conditionComments = comments(
      in: ternary.condition.trailingTrivia + ternary.questionMark.leadingTrivia,
      indentation: indentation.base
    )
    let thenLeadingComments = comments(
      in: ternary.questionMark.trailingTrivia + ternary.thenExpression.leadingTrivia,
      indentation: bodyIndentation
    )
    let thenTrailingComments = comments(
      in: ternary.thenExpression.trailingTrivia + ternary.colon.leadingTrivia,
      indentation: bodyIndentation
    )
    let elseLeadingComments = comments(
      in: ternary.colon.trailingTrivia + ternary.elseExpression.leadingTrivia,
      indentation: bodyIndentation
    )

    let condition = ternary.condition
      .with(\.leadingTrivia, [])
      .with(\.trailingTrivia, conditionComments.isEmpty ? [] : .space + conditionComments)

    func body(_ expr: ExprSyntax, leadingComments: Trivia, trailingComments: Trivia) -> CodeBlockSyntax {
      var leadingTrivia: Trivia = .newline + bodyIndentation
      if !leadingComments.isEmpty {
        leadingTrivia += leadingComments + separator(after: leadingComments, indentation: bodyIndentation)
      }
      return CodeBlockSyntax(
        leftBrace: .leftBraceToken(),
        statements: [
          CodeBlockItemSyntax(
            item: .expr(
              expr
                .with(\.leadingTrivia, leadingTrivia)
                .with(\.trailingTrivia, trailingComments.isEmpty ? [] : .space + trailingComments)
            )
          )
        ],
        rightBrace: .rightBraceToken(leadingTrivia: .newline + indentation.base)
      )
    }

    return IfExprSyntax(
      // Comments in front of the ternary expression, like `// test` in `// test\nfoo ? 1 : 2`, stay in front of `if`.
      leadingTrivia: ternary.leadingTrivia,
      ifKeyword: .keyword(.if, trailingTrivia: .space),
      conditions: [ConditionElementSyntax(condition: .expression(condition))],
      body: body(ternary.thenExpression, leadingComments: thenLeadingComments, trailingComments: thenTrailingComments)
        .with(\.leftBrace.leadingTrivia, separator(after: conditionComments, indentation: indentation.base)),
      elseKeyword: .keyword(.else, leadingTrivia: .space, trailingTrivia: .space),
      elseBody: .codeBlock(body(ternary.elseExpression, leadingComments: elseLeadingComments, trailingComments: [])),
      // Comments after the ternary expression stay after the `if` expression.
      trailingTrivia: ternary.trailingTrivia
    )
  }

  /// The comments in `trivia` without the whitespace around them.
  ///
  /// Comments that were on separate lines stay on separate lines, indented by `indentation`.
  private static func comments(in trivia: Trivia, indentation: Trivia) -> Trivia {
    var result: Trivia = []
    var isOnNewLine = false
    for piece in trivia {
      if piece.isNewline {
        isOnNewLine = true
      } else if !piece.isWhitespace {
        if !result.isEmpty {
          result += isOnNewLine ? .newline + indentation : .space
        }
        result += Trivia(pieces: [piece])
        isOnNewLine = false
      }
    }
    return result
  }

  /// The trivia to insert between `comments` and the next token.
  ///
  /// The next token needs to go on a new line if the comments end with a line comment.
  private static func separator(after comments: Trivia, indentation: Trivia) -> Trivia {
    switch comments.pieces.last {
    case .lineComment, .docLineComment:
      return .newline + indentation
    default:
      return .space
    }
  }
}
