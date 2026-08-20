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
internal import LanguageServerProtocol
internal import SourceKitLSP
import SwiftBasicFormat
import SwiftExtensions
@_spi(Experimental) import SwiftLexicalLookup
import SwiftOperators
import SwiftRefactor
import SwiftSyntax

/// A code action that replaces a local variable with its assigned value at all usage sites.
struct InlineVariable: SyntaxRefactoringCodeActionProvider {
  package static let title: String = "Inline variable"

  package static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> PatternBindingSyntax? {
    guard let node = scope.innermostNodeContainingRange else { return nil }

    let variableDecl =
      node.firstMatch(ofType: VariableDeclSyntax.self)
      ?? node.as(CodeBlockItemSyntax.self)?.item.as(VariableDeclSyntax.self)

    guard let variableDecl = variableDecl,
      variableDecl.bindingSpecifier.tokenKind == .keyword(.let)
    else {
      return nil
    }

    // If the cursor is on the identifier or value, return the specific pattern binding.
    if let specificBinding = node.firstMatch(ofType: PatternBindingSyntax.self) {
      return specificBinding
    }

    return variableDecl.bindings.first
  }

  package static func textRefactor(syntax binding: PatternBindingSyntax, in context: Void) throws -> [SourceEdit] {
    guard let variableDecl = binding.parent?.parent?.as(VariableDeclSyntax.self),
      let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let initializer = binding.initializer?.value
    else {
      throw RefactoringNotApplicableError("Could not extract variable information")
    }

    let targetIdentifier = identifierPattern.identifier.text

    guard let blockScope = variableDecl.firstMatch(ofType: CodeBlockItemListSyntax.self) else {
      throw RefactoringNotApplicableError("Could not find the lexical scope for this variable")
    }

    // Resolve usage sites via SwiftLexicalLookup
    let usageSites = findValidUsages(
      targetIdentifier: targetIdentifier,
      targetBinding: binding,
      in: blockScope
    )

    guard !usageSites.isEmpty else {
      throw RefactoringNotApplicableError("Variable is never used")
    }

    guard canDuplicateInitializer(initializer, usageCount: usageSites.count) else {
      throw RefactoringNotApplicableError(
        "Inlining this variable would unsafely duplicate a potentially side-effecting initializer"
      )
    }

    var edits: [SourceEdit] = []
    let operatorTable = OperatorTable.standardOperators

    for usageNode in usageSites {
      let replacementText = formatReplacement(
        initializer: initializer,
        usageNode: usageNode,
        operatorTable: operatorTable
      )

      // Exclude trailing trivia so range precisely matches the token
      let editRange = usageNode.positionAfterSkippingLeadingTrivia..<usageNode.endPositionBeforeTrailingTrivia
      edits.append(SourceEdit(range: editRange, replacement: replacementText))
    }

    // If this is the only variable in the declaration (e.g., `let x = 1`),
    // remove the entire code block item.
    if variableDecl.bindings.count == 1,
      let codeBlockItem = variableDecl.parent?.as(CodeBlockItemSyntax.self)
    {
      let range = codeBlockItem.position..<codeBlockItem.endPosition
      edits.append(SourceEdit(range: range, replacement: ""))
    } else {
      // If there are multiple bindings (e.g., `let x = 1, y = 2`),
      // remove only the target binding and clean up the trailing commas.
      var newBindingsArray = Array(variableDecl.bindings)
      newBindingsArray.removeAll { $0.id == binding.id }

      if !newBindingsArray.isEmpty {
        newBindingsArray[0].leadingTrivia = []
        newBindingsArray[newBindingsArray.count - 1].trailingComma = nil
      }

      var newDecl = variableDecl.with(\.bindings, PatternBindingListSyntax(newBindingsArray))
      newDecl.leadingTrivia = []

      let range = variableDecl.positionAfterSkippingLeadingTrivia..<variableDecl.endPosition
      edits.append(SourceEdit(range: range, replacement: newDecl.description))
    }

    return edits
  }

  private static func findValidUsages(
    targetIdentifier: String,
    targetBinding: PatternBindingSyntax,
    in scope: CodeBlockItemListSyntax
  ) -> [DeclReferenceExprSyntax] {
    let finder = ReferenceCollector(targetIdentifier: targetIdentifier)
    finder.walk(scope)

    return finder.candidates.filter { usageNode in
      guard usageNode.position > targetBinding.endPosition else { return false }

      let lookupResults = usageNode.lookup(Identifier(usageNode.baseName))

      for result in lookupResults {
        switch result {
        case .fromScope(_, let names):
          let matchesTarget = names.contains { name in
            if let resolvedBinding = name.syntax.firstMatch(ofType: PatternBindingSyntax.self) {
              return resolvedBinding.id == targetBinding.id
            }

            if let resolvedDecl = name.syntax.firstMatch(ofType: VariableDeclSyntax.self),
              let targetDecl = targetBinding.firstMatch(ofType: VariableDeclSyntax.self)
            {
              return resolvedDecl.id == targetDecl.id
            }

            return false
          }

          if matchesTarget {
            return true
          }

          // A closer declaration shadows the target binding, so do not continue
          // searching outer scopes for another matching declaration.
          return false

        default:
          continue
        }
      }
      return false
    }
  }

  /// Determines whether it is safe to inline the initializer at multiple usage sites.
  /// If the initializer has side effects (like a function call), duplicating it could
  /// change the program's behavior.
  private static func canDuplicateInitializer(
    _ initializer: ExprSyntax,
    usageCount: Int
  ) -> Bool {
    guard usageCount > 1 else {
      return true
    }

    return isObviouslySideEffectFree(initializer)
  }

  /// Returns `true` for literals, variable references, and basic collections of these.
  private static func isObviouslySideEffectFree(_ expr: ExprSyntax) -> Bool {
    if expr.is(IntegerLiteralExprSyntax.self) || expr.is(FloatLiteralExprSyntax.self)
      || expr.is(BooleanLiteralExprSyntax.self) || expr.is(StringLiteralExprSyntax.self)
      || expr.is(NilLiteralExprSyntax.self) || expr.is(DeclReferenceExprSyntax.self)
    {
      return true
    }

    if let arrayExpr = expr.as(ArrayExprSyntax.self) {
      return arrayExpr.elements.allSatisfy { isObviouslySideEffectFree($0.expression) }
    }

    if let dictExpr = expr.as(DictionaryExprSyntax.self) {
      if let elements = dictExpr.content.as(DictionaryElementListSyntax.self) {
        return elements.allSatisfy {
          isObviouslySideEffectFree($0.key) && isObviouslySideEffectFree($0.value)
        }
      }
      return true
    }

    if let tupleExpr = expr.as(TupleExprSyntax.self) {
      return tupleExpr.elements.allSatisfy { isObviouslySideEffectFree($0.expression) }
    }

    return false
  }

  static func formatReplacement(
    initializer: ExprSyntax,
    usageNode: DeclReferenceExprSyntax,
    operatorTable: OperatorTable
  ) -> String {
    if isPrimaryExpression(initializer) {
      return initializer.description
    }

    if needsParentheses(initializer: initializer, usageNode: usageNode, operatorTable: operatorTable) {
      return "(\(initializer.description.trimmingCharacters(in: .whitespacesAndNewlines)))"
    }

    return initializer.description
  }

  static func isPrimaryExpression(_ expr: ExprSyntax) -> Bool {
    expr.is(IntegerLiteralExprSyntax.self) || expr.is(FloatLiteralExprSyntax.self)
      || expr.is(BooleanLiteralExprSyntax.self) || expr.is(StringLiteralExprSyntax.self)
      || expr.is(NilLiteralExprSyntax.self) || expr.is(DeclReferenceExprSyntax.self)
      || expr.is(FunctionCallExprSyntax.self) || expr.is(MemberAccessExprSyntax.self)
      || expr.is(SubscriptCallExprSyntax.self) || expr.is(ArrayExprSyntax.self) || expr.is(DictionaryExprSyntax.self)
      || expr.is(TupleExprSyntax.self) || expr.is(ClosureExprSyntax.self)
  }

  // Determine whether replacing the reference with the initializer would
  // change the expression's operator grouping.
  static func needsParentheses(
    initializer: ExprSyntax,
    usageNode: DeclReferenceExprSyntax,
    operatorTable: OperatorTable
  ) -> Bool {
    guard let parent = usageNode.parent else { return false }

    if parent.is(MemberAccessExprSyntax.self) || parent.is(SubscriptCallExprSyntax.self)
      || parent.is(FunctionCallExprSyntax.self) || parent.is(PrefixOperatorExprSyntax.self)
      || parent.is(PostfixOperatorExprSyntax.self)
    {
      return !isPrimaryExpression(initializer)
    }

    let parentSeq = parent.as(SequenceExprSyntax.self) ?? parent.parent?.as(SequenceExprSyntax.self)

    guard let parentSeq = parentSeq else {
      return !isPrimaryExpression(initializer)
    }

    var newElements: [ExprSyntax] = []
    var replaced = false

    for element in parentSeq.elements {
      if element.id == usageNode.id {
        replaced = true
        if let initSeq = initializer.as(SequenceExprSyntax.self) {
          for initElement in initSeq.elements {
            newElements.append(initElement)
          }
        } else {
          newElements.append(initializer)
        }
      } else {
        newElements.append(element)
      }
    }

    guard replaced else { return !isPrimaryExpression(initializer) }

    let combinedSeq = SequenceExprSyntax(elements: ExprListSyntax(newElements))

    do {
      let foldedCombined = try operatorTable.foldSingle(combinedSeq)

      let foldedInit: ExprSyntax
      if let initSeq = initializer.as(SequenceExprSyntax.self) {
        foldedInit = try operatorTable.foldSingle(initSeq)
      } else {
        foldedInit = initializer
      }

      let targetString = foldedInit.description.trimmingCharacters(in: .whitespacesAndNewlines)
      return !containsMatchingSubtree(Syntax(foldedCombined), target: targetString)
    } catch {
      return true
    }
  }

  // Check whether the initializer remains grouped as a single expression
  // after the containing sequence is folded.
  static func containsMatchingSubtree(_ node: Syntax, target: String) -> Bool {
    if node.description.trimmingCharacters(in: .whitespacesAndNewlines) == target {
      return true
    }
    for child in node.children(viewMode: .sourceAccurate) {
      if containsMatchingSubtree(child, target: target) {
        return true
      }
    }
    return false
  }
}

/// A syntax visitor that finds all references to a specific identifier name.
/// This acts as a preliminary filter before using `SwiftLexicalLookup` to verify scope.
final class ReferenceCollector: SyntaxVisitor {
  let targetIdentifier: String
  var candidates: [DeclReferenceExprSyntax] = []

  init(targetIdentifier: String) {
    self.targetIdentifier = targetIdentifier
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if node.baseName.text == targetIdentifier {
      candidates.append(node)
    }
    return .visitChildren
  }
}

extension SyntaxProtocol {
  /// Traverses up the syntax tree to find the first ancestor of the specified type.
  func firstMatch<T: SyntaxProtocol>(ofType type: T.Type) -> T? {
    var current: Syntax? = Syntax(self)
    while let node = current {
      if let match = node.as(T.self) { return match }
      current = node.parent
    }
    return nil
  }
}
