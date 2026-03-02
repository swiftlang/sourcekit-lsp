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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

/// Inline temp variable: replace a temporary `let` binding with its value at all usage sites,
/// then remove the declaration.
///
/// ## Before
/// ```swift
/// func example() {
///     let basePrice = item.price
///     let total = basePrice * quantity
/// }
/// ```
///
/// ## After
/// ```swift
/// func example() {
///     let total = item.price * quantity
/// }
/// ```
///
/// When the inlined value is an expression that may need parentheses for precedence (e.g. `1 + 2`
/// inlined into `basePrice * 3`), parentheses are added: `(1 + 2) * 3`.
@_spi(Testing) public struct InlineTempVariable: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let (variableDecl, name, initializer, codeBlock, declItem) = findInlineableBinding(in: scope) else {
      return []
    }

    let references = collectReferences(to: name, after: variableDecl.endPosition, in: codeBlock)
    guard !references.isEmpty else {
      return []
    }

    let snapshot = scope.snapshot
    var textEdits: [TextEdit] = []

    // Replace each reference with the initializer value, adding parentheses when needed for precedence.
    for ref in references {
      let replacementText = replacementTextForInlining(
        initializer: initializer,
        at: ref,
        in: codeBlock
      )
      textEdits.append(TextEdit(
        range: snapshot.range(of: ref),
        newText: replacementText
      ))
    }

    // Remove the declaration (the entire code block item so we remove the newline too).
    textEdits.append(TextEdit(
      range: snapshot.range(of: declItem),
      newText: ""
    ))

    // Apply edits from end to start so earlier edits don't invalidate positions.
    textEdits.sort { $0.range.lowerBound > $1.range.lowerBound }

    return [
      CodeAction(
        title: "Inline variable",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [snapshot.uri: textEdits])
      )
    ]
  }

  /// Finds a `let name = expr` binding that can be inlined, and its enclosing code block and item.
  private static func findInlineableBinding(in scope: SyntaxCodeActionScope)
    -> (VariableDeclSyntax, name: String, initializer: ExprSyntax, CodeBlockSyntax, CodeBlockItemSyntax)? {
    guard let node = scope.innermostNodeContainingRange else {
      return nil
    }

    let variableDecl = node.findParentOfSelf(
      ofType: VariableDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
    guard let variableDecl, variableDecl.bindingSpecifier.tokenKind == .keyword(.let) else {
      return nil
    }

    guard let binding = variableDecl.bindings.only,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let initializer = binding.initializer?.value
    else {
      return nil
    }

    let name = pattern.identifier.text
    guard !name.isEmpty else {
      return nil
    }

    guard let codeBlockItem = variableDecl.parent?.as(CodeBlockItemSyntax.self),
      let codeBlockItemList = codeBlockItem.parent?.as(CodeBlockItemListSyntax.self),
      let codeBlock = codeBlockItemList.parent?.as(CodeBlockSyntax.self)
    else {
      return nil
    }

    return (variableDecl, name, initializer, codeBlock, codeBlockItem)
  }

  /// Collects all `DeclReferenceExprSyntax` in `block` that reference `name` and occur after `afterPosition`.
  private static func collectReferences(
    to name: String,
    after afterPosition: AbsolutePosition,
    in block: CodeBlockSyntax
  ) -> [DeclReferenceExprSyntax] {
    let collector = DeclReferenceCollector(name: name, afterPosition: afterPosition)
    collector.walk(block)
    return collector.references
  }

  /// Returns the text to use when inlining `initializer` at the given reference site.
  /// Adds parentheses when needed to preserve precedence (e.g. `1 + 2` inlined into `x * 3` → `(1 + 2) * 3`).
  private static func replacementTextForInlining(
    initializer: ExprSyntax,
    at reference: DeclReferenceExprSyntax,
    in codeBlock: CodeBlockSyntax
  ) -> String {
    let needsParens = initializerNeedsParenthesesAtUseSite(initializer, reference: reference)
    if needsParens {
      return "(\(initializer.trimmed))"
    }
    return initializer.trimmed.description
  }

  /// Returns true if the initializer expression should be wrapped in parentheses when inlined at the reference.
  /// This preserves correctness when the initializer contains operators with lower precedence than the context
  /// (e.g. inlining `1 + 2` into `basePrice * 3` must yield `(1 + 2) * 3`).
  private static func initializerNeedsParenthesesAtUseSite(
    _ initializer: ExprSyntax,
    reference: DeclReferenceExprSyntax
  ) -> Bool {
    // Simple expressions (literals, single identifiers, member access) don't need parens.
    if !initializer.isCompositeForInlining {
      return false
    }

    // The reference is used as an operand if its parent is an expression that has multiple children
    // (e.g. binary op, function call). In those cases we need parens for the inlined value.
    guard let parent = reference.parent else {
      return false
    }

    if parent.is(InfixOperatorExprSyntax.self) {
      return true
    }
    if parent.is(SequenceExprSyntax.self) {
      return true
    }
    if parent.is(TernaryExprSyntax.self) {
      return true
    }
    if parent.is(FunctionCallExprSyntax.self) {
      return true
    }
    if parent.is(SubscriptCallExprSyntax.self) {
      return true
    }
    if parent.is(AwaitExprSyntax.self) || parent.is(TryExprSyntax.self) {
      return true
    }

    return false
  }
}

// MARK: - DeclReferenceCollector

private final class DeclReferenceCollector: SyntaxVisitor {
  private let name: String
  private let afterPosition: AbsolutePosition
  private(set) var references: [DeclReferenceExprSyntax] = []

  init(name: String, afterPosition: AbsolutePosition) {
    self.name = name
    self.afterPosition = afterPosition
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if node.baseName.text == name, node.position >= afterPosition {
      references.append(node)
    }
    return .visitChildren
  }
}

// MARK: - Helpers

private extension ExprSyntax {
  /// Whether this expression is "composite" for the purpose of inlining: if inlined into another
  /// expression, it may need parentheses to preserve meaning (e.g. `1 + 2` in `x * 3`).
  var isCompositeForInlining: Bool {
    switch self.kind {
    case .arrayExpr, .booleanLiteralExpr, .closureExpr, .declReferenceExpr, .dictionaryExpr,
      .floatLiteralExpr, .integerLiteralExpr, .nilLiteralExpr, .stringLiteralExpr, .superExpr:
      return false
    case .memberAccessExpr:
      return false
    case .tupleExpr:
      if let single = self.as(TupleExprSyntax.self)?.elements.only, single.label == nil {
        return single.expression.isCompositeForInlining
      }
      return true
    default:
      return true
    }
  }

  var trimmed: ExprSyntax {
    self.with(\.leadingTrivia, []).with(\.trailingTrivia, [])
  }
}
