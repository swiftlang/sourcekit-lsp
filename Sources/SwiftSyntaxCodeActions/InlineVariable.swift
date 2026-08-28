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
import SwiftParser
import SwiftRefactor
import SwiftSyntax

/// A code action that replaces a local variable with its assigned value at all usage sites.
struct InlineVariable: SyntaxRefactoringCodeActionProvider {
  package static let title: String = "Inline variable"

  package static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> PatternBindingSyntax? {
    guard let node = scope.innermostNodeContainingRange else { return nil }

    let variableDecl =
      node.ancestorOrSelf(mapping: { $0.as(VariableDeclSyntax.self) })
      ?? node.as(CodeBlockItemSyntax.self)?.item.as(VariableDeclSyntax.self)

    guard let variableDecl = variableDecl,
      variableDecl.bindingSpecifier.tokenKind == .keyword(.let)
    else {
      return nil
    }

    // If the cursor is on the identifier or value, return the specific pattern binding.
    if let specificBinding = node.ancestorOrSelf(mapping: { $0.as(PatternBindingSyntax.self) }) {
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

    guard let targetIdentifier = Identifier(identifierPattern.identifier) else {
      throw RefactoringNotApplicableError("Could not parse the target identifier")
    }

    guard let blockScope = variableDecl.ancestorOrSelf(mapping: { $0.as(CodeBlockItemListSyntax.self) }) else {
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

    var edits: [SourceEdit] = []

    for usageNode in usageSites {
      let replacementText = formatReplacement(
        initializer: initializer,
        usageNode: usageNode
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
    targetIdentifier: Identifier,
    targetBinding: PatternBindingSyntax,
    in scope: CodeBlockItemListSyntax
  ) -> [DeclReferenceExprSyntax] {
    let finder = ReferenceCollector(
      targetIdentifier: targetIdentifier,
      targetBinding: targetBinding
    )
    finder.walk(scope)
    return finder.candidates
  }

  static func formatReplacement(
    initializer: ExprSyntax,
    usageNode: DeclReferenceExprSyntax
  ) -> String {
    if needsParentheses(initializer: initializer, usageNode: usageNode) {
      return "(\(initializer.description.trimmingCharacters(in: .whitespacesAndNewlines)))"
    }
    return initializer.description
  }

  static func needsParentheses(
    initializer: ExprSyntax,
    usageNode: DeclReferenceExprSyntax
  ) -> Bool {
    let root = usageNode.root
    let fullText = root.description
    let initializerText = initializer.description.trimmingCharacters(in: .whitespacesAndNewlines)

    let startPos = usageNode.positionAfterSkippingLeadingTrivia.utf8Offset
    let endPos = usageNode.endPositionBeforeTrailingTrivia.utf8Offset

    let startIdx = fullText.utf8.index(fullText.utf8.startIndex, offsetBy: startPos)
    let endIdx = fullText.utf8.index(fullText.utf8.startIndex, offsetBy: endPos)

    var rewrittenText = fullText
    rewrittenText.replaceSubrange(startIdx..<endIdx, with: initializerText)

    let parsedFile = Parser.parse(source: rewrittenText)

    if parsedFile.hasError {
      return true
    }

    let targetSpan = startPos..<(startPos + initializerText.utf8.count)
    return !containsNode(in: Syntax(parsedFile), withSpan: targetSpan, matching: initializerText)
  }

  static func containsNode(
    in node: Syntax,
    withSpan span: Range<Int>,
    matching text: String
  ) -> Bool {
    let nodeStart = node.positionAfterSkippingLeadingTrivia.utf8Offset
    let nodeEnd = node.endPositionBeforeTrailingTrivia.utf8Offset

    if nodeStart == span.lowerBound && nodeEnd == span.upperBound {
      if node.description.trimmingCharacters(in: .whitespacesAndNewlines) == text {
        return true
      }
    }

    for child in node.children(viewMode: .sourceAccurate) {
      let childFullStart = child.position.utf8Offset
      let childFullEnd = child.endPosition.utf8Offset

      if childFullStart <= span.upperBound && childFullEnd >= span.lowerBound {
        if containsNode(in: child, withSpan: span, matching: text) {
          return true
        }
      }
    }

    return false
  }
}

/// A syntax visitor that finds all references to a specific identifier name
/// and verifies they resolve to the target binding using `SwiftLexicalLookup`.
final class ReferenceCollector: SyntaxVisitor {
  let targetIdentifier: Identifier
  let targetBinding: PatternBindingSyntax
  var candidates: [DeclReferenceExprSyntax] = []

  init(targetIdentifier: Identifier, targetBinding: PatternBindingSyntax) {
    self.targetIdentifier = targetIdentifier
    self.targetBinding = targetBinding
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    guard let nodeIdentifier = Identifier(node.baseName),
      nodeIdentifier == targetIdentifier,
      node.position > targetBinding.endPosition
    else {
      return .visitChildren
    }

    let lookupResults = node.lookup(nodeIdentifier)
    for result in lookupResults {
      switch result {
      case .fromScope(_, let names):
        let matchesTarget = names.contains { name in
          name.syntax.id == targetBinding.id || name.syntax.id == targetBinding.pattern.id
        }

        if matchesTarget {
          candidates.append(node)
          return .visitChildren
        }
        return .visitChildren
      default:
        continue
      }
    }

    return .visitChildren
  }
}
