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
import SwiftSyntax

/// A code action that inlines a temporary variable by replacing all references
/// to it with its initializer expression, then removing the declaration.
///
/// The action is offered when the cursor is on a `let` or `var` declaration
/// with a single binding that has an initializer and no type annotation.
///
/// **Before:**
/// ```swift
/// let basePrice = item.price
/// let total = basePrice * quantity
/// ```
///
/// **After:**
/// ```swift
/// let total = item.price * quantity
/// ```
struct InlineTempVariable: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    // Find the variable declaration the cursor is on.
    guard let varDecl = scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: VariableDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    ) else {
      return []
    }

    // Only support single-binding declarations.
    guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else {
      return []
    }

    // Must have a simple identifier pattern and an initializer.
    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let initializer = binding.initializer?.value
    else {
      return []
    }

    // Don't inline if there's a type annotation — the user likely wants it explicit.
    if binding.typeAnnotation != nil {
      return []
    }

    let variableName = pattern.identifier.text

    // Find the parent code block that contains this declaration.
    guard let codeBlockItem = varDecl.parent?.as(CodeBlockItemSyntax.self),
      let codeBlockItemList = codeBlockItem.parent?.as(CodeBlockItemListSyntax.self)
    else {
      return []
    }

    // Find the index of this declaration in the code block.
    guard let declIndex = codeBlockItemList.firstIndex(where: { $0.id == codeBlockItem.id }) else {
      return []
    }

    // Collect all statements after the declaration.
    let subsequentStatements = codeBlockItemList[codeBlockItemList.index(after: declIndex)...]

    // Find all references to the variable in subsequent statements.
    let references = findReferences(to: variableName, in: Array(subsequentStatements))

    // Only offer the action if the variable is actually used.
    if references.isEmpty {
      return []
    }

    // Don't inline if the variable is used as an inout argument or is reassigned.
    for ref in references {
      if isInoutArgument(ref) || isAssignmentTarget(ref) {
        return []
      }
    }

    // Build text edits: replace each reference with the initializer, then remove the declaration.
    var textEdits: [TextEdit] = []

    // For each reference, replace the identifier with the initializer expression.
    let initializerText = initializer.description.trimmingCharacters(in: .whitespaces)

    // Determine if we need parentheses around the inlined expression.
    let needsParens = initializerNeedsParentheses(initializer)
    let replacementText = needsParens ? "(\(initializerText))" : initializerText

    for ref in references {
      let startPos = scope.snapshot.position(of: ref.positionAfterSkippingLeadingTrivia)
      let endPos = scope.snapshot.position(of: ref.endPositionBeforeTrailingTrivia)
      textEdits.append(
        TextEdit(
          range: startPos..<endPos,
          newText: replacementText
        )
      )
    }

    // Remove the entire declaration statement including trailing newline.
    let declStart = scope.snapshot.position(of: codeBlockItem.positionAfterSkippingLeadingTrivia)
    let declEnd: Position
    let nextIndex = codeBlockItemList.index(after: declIndex)
    if nextIndex < codeBlockItemList.endIndex {
      declEnd = scope.snapshot.position(of: codeBlockItemList[nextIndex].positionAfterSkippingLeadingTrivia)
    } else {
      declEnd = scope.snapshot.position(of: codeBlockItem.endPositionBeforeTrailingTrivia)
    }

    textEdits.append(
      TextEdit(
        range: declStart..<declEnd,
        newText: ""
      )
    )

    return [
      CodeAction(
        title: "Inline '\(variableName)'",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: textEdits
          ]
        )
      )
    ]
  }
}

// MARK: - Helpers

/// Finds all `DeclReferenceExprSyntax` nodes that reference the given variable name.
private func findReferences(
  to variableName: String,
  in statements: [CodeBlockItemSyntax]
) -> [DeclReferenceExprSyntax] {
  var references: [DeclReferenceExprSyntax] = []
  for statement in statements {
    let collector = ReferenceCollector(variableName: variableName)
    collector.walk(statement)
    references.append(contentsOf: collector.references)
  }
  return references
}

private class ReferenceCollector: SyntaxVisitor {
  let variableName: String
  var references: [DeclReferenceExprSyntax] = []

  init(variableName: String) {
    self.variableName = variableName
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if node.baseName.text == variableName && node.argumentNames == nil {
      references.append(node)
    }
    return .visitChildren
  }
}

/// Checks if the given reference is used as an `&variable` inout argument.
private func isInoutArgument(_ ref: DeclReferenceExprSyntax) -> Bool {
  return ref.parent?.is(InOutExprSyntax.self) == true
}

/// Checks if the given reference is the target of an assignment.
private func isAssignmentTarget(_ ref: DeclReferenceExprSyntax) -> Bool {
  guard let infixExpr = ref.parent?.as(InfixOperatorExprSyntax.self) else {
    return false
  }
  // Check if this ref is on the left side and the operator is assignment.
  if infixExpr.leftOperand.as(DeclReferenceExprSyntax.self)?.id == ref.id,
    infixExpr.operator.as(AssignmentExprSyntax.self) != nil
  {
    return true
  }
  return false
}

/// Determines if the initializer expression needs parentheses when inlined
/// to avoid changing the meaning of the code.
///
/// For example, inlining `let x = a + b` into `x * c` should produce
/// `(a + b) * c`, not `a + b * c`.
private func initializerNeedsParentheses(_ expr: ExprSyntax) -> Bool {
  // Binary operations, ternary expressions, try/await, and closures
  // generally need parentheses when inlined.
  if expr.is(InfixOperatorExprSyntax.self)
    || expr.is(TernaryExprSyntax.self)
    || expr.is(TryExprSyntax.self)
    || expr.is(AwaitExprSyntax.self)
    || expr.is(AsExprSyntax.self)
    || expr.is(IsExprSyntax.self)
  {
    return true
  }
  return false
}
