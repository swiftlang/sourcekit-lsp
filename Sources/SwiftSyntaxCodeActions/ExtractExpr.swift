//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project.
//
// Copyright 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception.
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SourceKitLSP
import SwiftBasicFormat
import SwiftExtensions
import SwiftSyntax

/// Syntactic code action provider to extract the expression at the cursor
/// into a `let` constant declared before the enclosing statement.
///
/// ## Before
/// ```swift
/// func demo() {
///   print(a + 2 * 3)
/// }
/// ```
///
/// ## After (with the cursor inside `a + 2 * 3`)
/// ```swift
/// func demo() {
///   let result = a + 2 * 3
///   print(result)
/// }
/// ```
///
/// This is the swift-syntax based replacement for the sourcekitd
/// `source.refactoring.kind.extract.expr` refactoring action. Like the
/// original, the name is corrected to avoid collisions with names visible in
/// the enclosing code block, and expressions that provide little value are
/// rejected: bare identifiers, literals, and closure expressions.
@_spi(Testing) public struct ExtractExpr: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let extraction = findExtractableExpression(in: scope) else {
      return []
    }

    let declarationText =
      "let \(extraction.suggestedName) = \(extraction.expression.trimmedDescription)\n"

    // Replace the expression with the new name.
    let exprStart = extraction.expression.positionAfterSkippingLeadingTrivia
    let exprEnd = extraction.expression.endPosition
    let expressionRange = scope.snapshot.positionRange(
      of: exprStart..<exprEnd
    )
    let replaceEdit = TextEdit(range: expressionRange, newText: extraction.suggestedName)

    // Insert at the start of the statement's line so the declaration keeps
    // the statement's indentation and the following text stays indented.
    let firstToken = extraction.item.firstToken(viewMode: .sourceAccurate)
    let itemIndent = firstToken?.leadingTrivia.pieces.reversed().prefix { piece in
      switch piece {
      case .spaces, .tabs:
        return true
      default:
        return false
      }
    }.reduce(into: 0) { count, piece in count += piece.sourceLength.utf8Length } ?? 0
    let lineStart = firstToken?.positionAfterSkippingLeadingTrivia.advanced(
      by: -itemIndent
    ) ?? extraction.item.positionAfterSkippingLeadingTrivia
    let declarationPosition = scope.snapshot.position(of: lineStart)
    let indentation = String(repeating: " ", count: itemIndent)
    let edits = [
      TextEdit(
        range: declarationPosition..<declarationPosition,
        newText: indentation + declarationText
      ),
      replaceEdit,
    ]

    return [
      CodeAction(
        title: "Extract expression",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: edits])
      )
    ]
  }

  struct ExtractableExpression {
    let expression: ExprSyntax
    let item: CodeBlockItemSyntax
    let suggestedName: String
    let expressionIsWholeStatement: Bool
  }

  /// Walks up from the selection to find an extractable expression, its
  /// enclosing code block item, and a collision-free name.
  static func findExtractableExpression(
    in scope: SyntaxCodeActionScope
  ) -> ExtractableExpression? {
    guard let innermost = scope.innermostNodeContainingRange else {
      return nil
    }

    // Find the innermost expression that fully contains the selection by
    // walking up from the common ancestor. Stop at statement-level nodes.
    var node: Syntax? = Syntax(innermost)
    var expression: ExprSyntax?
    while let current = node {
      if let expr = current.as(ExprSyntax.self) {
        expression = expr
        break
      }
      if current.is(CodeBlockItemSyntax.self) {
        return nil
      }
      node = current.parent
    }
    guard var expression else {
      return nil
    }

    // A cursor directly on an operator token is ambiguous — Swift sequence
    // expressions are flat, so the intended sub-expression is unknowable
    // without an explicit selection. Don't offer the action (the sourcekitd
    // action likewise requires an explicit expression selection).
    if isPureOperator(expression) {
      return nil
    }

    // A cursor inside a member name or function name surfaces the bare
    // `DeclReferenceExpr` of that name; extract the full access/call
    // expression it belongs to instead (e.g. `names.joined()` from the
    // cursor inside `joined`).
    if let declRef = expression.as(DeclReferenceExprSyntax.self),
      let parentExpr = declRef.parent?.as(ExprSyntax.self)
    {
      expression = parentExpr
    }

    // A cursor inside the callee of a call surfaces the callee expression
    // (e.g. `names.joined`); extract the whole call instead. Walk up through
    // intermediate wrapper nodes until the owning call is found.
    var scopeNode: Syntax? = Syntax(expression)
    while let current = scopeNode {
      if let call = current.as(FunctionCallExprSyntax.self) {
        if call.calledExpression.trimmedRange == expression.trimmedRange {
          expression = ExprSyntax(call)
        }
        break
      }
      scopeNode = current.parent
    }

    // Parenthesized expressions: extracting the inner expression is more
    // useful than the parentheses.
    if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
      let inner = tuple.elements.first?.expression
    {
      expression = inner
    }

    // Don't extract expressions that provide little value (matching the
    // sourcekitd action): bare identifiers, literals, and closures.
    if expression.is(DeclReferenceExprSyntax.self) {
      return nil
    }
    if isLiteral(expression) {
      return nil
    }
    if expression.is(ClosureExprSyntax.self) {
      return nil
    }

    // The expression must be inside a code block item (a statement), which
    // transitively means we are in an executable context.
    guard let item = enclosingCodeBlockItem(of: expression) else {
      return nil
    }

    // Don't extract statements' own control structure: the expression being
    // a `let` initializer's value is fine, but a whole expression statement
    // needs the statement-replacement form of the edit.
    let expressionIsWholeStatement =
      item.trimmedDescription == expression.trimmedDescription
    if expressionIsWholeStatement {
      // The expression already forms its own statement — extracting it into a
      // constant provides no value (matches the sourcekitd action).
      return nil
    }

    // Reject expressions that contain any `guard` statement (syntactic
    // approximation of the original action's guard restriction) — `guard`
    // requires its enclosing scope to exit, and moving it into a `let`
    // initializer would not compile.
    if containsGuard(expression) {
      return nil
    }

    let name = uniqueName(base: "result", in: item)

    return ExtractableExpression(
      expression: expression,
      item: item,
      suggestedName: name,
      expressionIsWholeStatement: expressionIsWholeStatement
    )
  }


  /// The nearest ancestor of `node` that is an expression, skipping erased
  /// wrapper nodes whose dynamic casts fail.
  static func nearestAncestorExpr(of node: some SyntaxProtocol) -> ExprSyntax? {
    var current: Syntax? = Syntax(node).parent
    while let syntax = current {
      if let expr = syntax.as(ExprSyntax.self) {
        return expr
      }
      current = syntax.parent
    }
    return nil
  }

  static func isPureOperator(_ expr: ExprSyntax) -> Bool {
    expr.is(BinaryOperatorExprSyntax.self) || expr.is(PrefixOperatorExprSyntax.self)
      || expr.is(PostfixOperatorExprSyntax.self)
  }

  static func isLiteral(_ expr: ExprSyntax) -> Bool {
    switch expr.kind {
    case .integerLiteralExpr, .floatLiteralExpr, .stringLiteralExpr,
      .booleanLiteralExpr, .nilLiteralExpr,
      .regexLiteralExpr, .arrayExpr, .dictionaryExpr, .tupleExpr,
      .keyPathExpr, .macroExpansionExpr, .editorPlaceholderExpr:
      return true
    default:
      return false
    }
  }

  static func containsGuard(_ expr: ExprSyntax) -> Bool {
    var found = false
    func rec(_ s: Syntax) {
      if found { return }
      for child in s.children(viewMode: .sourceAccurate) {
        if child.is(GuardStmtSyntax.self) {
          found = true
          return
        }
        rec(child)
      }
    }
    rec(Syntax(expr))
    return found
  }

  /// The code block item statement that (transitively) contains `node`.
  static func enclosingCodeBlockItem(of node: some SyntaxProtocol) -> CodeBlockItemSyntax? {
    var current: Syntax? = Syntax(node)
    while let syntax = current {
      if let item = syntax.as(CodeBlockItemSyntax.self) {
        return item
      }
      current = syntax.parent
    }
    return nil
  }

  /// Generates a name of the form `result`, `result1`, `result2`, ... that
  /// does not collide with any identifier declared or used in the enclosing
  /// statement's code block.
  static func uniqueName(base: String, in item: CodeBlockItemSyntax) -> String {
    guard let list = enclosingCodeBlockItemList(of: item) else {
      return base
    }

    var taken = Set<String>()
    for token in list.tokens(viewMode: .sourceAccurate) {
      if case .identifier(let text) = token.tokenKind {
        taken.insert(text)
      }
    }

    if !taken.contains(base) {
      return base
    }
    var index = 1
    while taken.contains("\(base)\(index)") {
      index += 1
    }
    return "\(base)\(index)"
  }

  static func enclosingCodeBlockItemList(
    of item: CodeBlockItemSyntax
  ) -> CodeBlockItemListSyntax? {
    // Mirrors the known parent chain: CodeBlockItem -> CodeBlockItemList ->
    // CodeBlock.
    if let list = item.parent?.as(CodeBlockItemListSyntax.self) {
      return list
    }
    return item.parent?.parent?.as(CodeBlockItemListSyntax.self)
  }
}
