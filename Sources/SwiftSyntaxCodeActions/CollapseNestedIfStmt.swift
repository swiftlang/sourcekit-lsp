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
import SwiftRefactor
@_spi(RawSyntax) package import SwiftSyntax
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Collapses an `if` statement whose body only consists of another `if` statement into a single `if` statement that
/// has the conditions of both statements.
///
/// Neither of the `if` statements may have an `else` clause.
///
/// ## Before
///
/// ```swift
/// if let user {
///   if user.isAdmin {
///     deleteEverything()
///   }
/// }
/// ```
///
/// ## After
///
/// ```swift
/// if let user, user.isAdmin {
///   deleteEverything()
/// }
/// ```
package struct CollapseNestedIfStmt: SyntaxRefactoringProvider {
  package static func refactor(syntax outerIf: IfExprSyntax, in context: Void = ()) throws -> IfExprSyntax {
    guard !outerIf.hasError else {
      throw RefactoringNotApplicableError("syntax has errors")
    }
    guard outerIf.elseBody == nil else {
      throw RefactoringNotApplicableError("'if' statement has an 'else' clause")
    }
    guard let innerItem = outerIf.body.statements.only, let innerIf = ifStatement(in: innerItem) else {
      throw RefactoringNotApplicableError("body of the 'if' statement does not consist of a single 'if' statement")
    }
    guard innerIf.elseBody == nil else {
      throw RefactoringNotApplicableError("nested 'if' statement has an 'else' clause")
    }

    // The collapsed statement consists of the outer `if` keyword, the conditions of both statements and the body of
    // the nested `if`. The braces of the outer body and the nested `if` keyword are removed.
    let outerIndentation = indentationOfLine(of: outerIf.ifKeyword)
    let innerIndentation = indentationOfLine(of: innerIf.ifKeyword)
    // Removes the indentation that the nested `if` has relative to the outer `if`.
    func unindent<Node: SyntaxProtocol>(_ node: Node) -> Node {
      guard innerIndentation.count > outerIndentation.count, innerIndentation.starts(with: outerIndentation) else {
        return node
      }
      let indentationStep = Trivia(pieces: innerIndentation.dropFirst(outerIndentation.count))
      return IndentationRemover(indentation: indentationStep).rewrite(node).cast(Node.self)
    }

    // Separate the conditions of both statements by a comma. The trivia between the last outer condition and the outer
    // `{` as well as the trivia after the nested `if` keyword (usually both a single space) go after the comma.
    var conditions = outerIf.conditions
    let lastOuterConditionIndex = conditions.index(before: conditions.endIndex)
    let innerConditions = unindent(innerIf.conditions)
    var triviaAfterComma = conditions[lastOuterConditionIndex].trailingTrivia.merging(innerIf.ifKeyword.trailingTrivia)
    if (triviaAfterComma + (innerConditions.first?.leadingTrivia ?? [])).endsWithUnterminatedLineComment {
      triviaAfterComma = triviaAfterComma.droppingTrailingWhitespace + .newline
    }
    conditions[lastOuterConditionIndex].trailingTrivia = []
    conditions[lastOuterConditionIndex].trailingComma = .commaToken(trailingTrivia: triviaAfterComma)
    conditions += innerConditions

    var body = unindent(innerIf.body)

    // Keep comments from the outer body by moving them into the collapsed body.
    let triviaBeforeInnerIf =
      outerIf.body.leftBrace.leadingTrivia + outerIf.body.leftBrace.trailingTrivia + innerItem.leadingTrivia
    var triviaAfterInnerIf = outerIf.body.rightBrace.leadingTrivia
    if innerItem.trailingTrivia.contains(where: \.isComment) {
      // The line of the nested `if`'s `}` is removed, so put comments that followed it on their own line.
      triviaAfterInnerIf =
        [.newlines(1)] + Trivia(pieces: innerIndentation) + innerItem.trailingTrivia.droppingLeadingWhitespace
        + triviaAfterInnerIf
    }
    if triviaBeforeInnerIf.contains(where: \.isComment) {
      body.leftBrace.trailingTrivia = body.leftBrace.trailingTrivia.droppingTrailingWhitespace
      if var firstStatement = body.statements.first {
        firstStatement.leadingTrivia = triviaBeforeInnerIf.insertingComments(before: firstStatement.leadingTrivia)
        body.statements[body.statements.startIndex] = firstStatement
      } else {
        triviaAfterInnerIf = triviaBeforeInnerIf.droppingTrailingWhitespace + triviaAfterInnerIf
      }
    }
    if triviaAfterInnerIf.contains(where: \.isComment) {
      body.rightBrace.leadingTrivia = body.rightBrace.leadingTrivia.droppingTrailingWhitespace + triviaAfterInnerIf
      if body.rightBrace.leadingTrivia.endsWithUnterminatedLineComment {
        body.rightBrace.leadingTrivia = body.rightBrace.leadingTrivia.droppingTrailingWhitespace + .newline
      }
    }
    body.rightBrace.trailingTrivia = outerIf.body.rightBrace.trailingTrivia

    return outerIf.with(\.conditions, conditions).with(\.body, body)
  }

  /// If `item` is an `if` statement, return it.
  private static func ifStatement(in item: CodeBlockItemSyntax) -> IfExprSyntax? {
    switch item.item {
    case .expr(let expr):
      return expr.as(IfExprSyntax.self)
    case .stmt(let stmt):
      return stmt.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)
    case .decl:
      return nil
    }
  }

  /// The indentation of the line that `token` is on.
  private static func indentationOfLine(of token: TokenSyntax) -> [TriviaPiece] {
    // `TokenSyntax.indentationOfLine` doesn't return the indentation of the token itself if it is preceded by a comment,
    // so compute the indentation from the leading trivia if the token starts a new line.
    let leadingTrivia = token.leadingTrivia.decomposed.pieces
    if let lastNewline = leadingTrivia.lastIndex(where: \.isNewline) {
      return Array(leadingTrivia[(lastNewline + 1)...].prefix(while: \.isWhitespace))
    }
    if token.previousToken(viewMode: .sourceAccurate) == nil {
      return Array(leadingTrivia.prefix(while: \.isWhitespace))
    }
    return token.indentationOfLine.decomposed.pieces
  }
}

extension CollapseNestedIfStmt: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Collapse Nested If Statements" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> IfExprSyntax? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IfExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

private extension Trivia {
  /// Whether this trivia ends with a line comment that isn't followed by a newline, i.e. the comment would swallow a
  /// token that immediately follows this trivia.
  var endsWithUnterminatedLineComment: Bool {
    for piece in self.reversed() {
      switch piece {
      case .lineComment, .docLineComment:
        return true
      case _ where piece.isNewline:
        return false
      default:
        continue
      }
    }
    return false
  }

  /// Assuming that `self` is trivia of tokens that were removed, return the leading trivia of the token following
  /// `self`, whose leading trivia is currently `leadingTrivia`, such that the comments in `self` are placed in front of
  /// that token.
  func insertingComments(before leadingTrivia: Trivia) -> Trivia {
    let comments = self.droppingTrailingWhitespace
    if leadingTrivia.first?.isNewline ?? false {
      return comments + leadingTrivia
    }
    // The token is on the same line as the token before it. Keep the line break that followed the comments, if any.
    let whitespaceAfterComments = Trivia(pieces: self.dropFirst(comments.count))
    let result = comments + whitespaceAfterComments + leadingTrivia.droppingLeadingWhitespace
    if result.endsWithUnterminatedLineComment {
      return result.droppingTrailingWhitespace + .newline
    }
    return result
  }
}
