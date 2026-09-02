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
    var current: Syntax? = Syntax(node)
    while let syntax = current {
      if let binding = syntax.as(PatternBindingSyntax.self) {
        guard let variableDecl = binding.parent?.parent?.as(VariableDeclSyntax.self),
          variableDecl.bindingSpecifier.tokenKind == .keyword(.let)
        else {
          return nil
        }
        return binding
      }
      if let variableDecl = syntax.as(VariableDeclSyntax.self) {
        guard variableDecl.bindingSpecifier.tokenKind == .keyword(.let) else {
          return nil
        }
        return variableDecl.bindings.first
      }
      if syntax.is(CodeBlockSyntax.self) || syntax.is(MemberBlockSyntax.self) {
        return nil
      }
      current = syntax.parent
    }
    return nil
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

    guard let blockScope = variableDecl.parent?.parent?.as(CodeBlockItemListSyntax.self) else {
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
      let parenthesized = TupleExprSyntax(
        leftParen: .leftParenToken(leadingTrivia: initializer.leadingTrivia),
        elements: [
          LabeledExprSyntax(
            expression:
              initializer
              .with(\.leadingTrivia, [])
              .with(\.trailingTrivia, [])
          )
        ],
        rightParen: .rightParenToken(trailingTrivia: initializer.trailingTrivia)
      )
      return parenthesized.description
    }
    return initializer.description
  }

  static func needsParentheses(
    initializer: ExprSyntax,
    usageNode: DeclReferenceExprSyntax
  ) -> Bool {
    guard let codeBlockItem = usageNode.ancestorOrSelf(mapping: { $0.as(CodeBlockItemSyntax.self) }) else {
      return true
    }
    let scopeText = codeBlockItem.description
    let initializerText = initializer.description

    let scopeStartOffset = codeBlockItem.position.utf8Offset
    let startPos = usageNode.positionAfterSkippingLeadingTrivia.utf8Offset - scopeStartOffset
    let endPos = usageNode.endPositionBeforeTrailingTrivia.utf8Offset - scopeStartOffset

    let startIdx = scopeText.utf8.index(scopeText.utf8.startIndex, offsetBy: startPos)
    let endIdx = scopeText.utf8.index(scopeText.utf8.startIndex, offsetBy: endPos)

    var rewrittenText = scopeText
    rewrittenText.replaceSubrange(startIdx..<endIdx, with: initializerText)

    var parser = Parser(rewrittenText)
    let parsedScope = CodeBlockItemSyntax.parse(from: &parser)
    if parsedScope.hasError {
      return true
    }

    let targetSpanStart = AbsolutePosition(utf8Offset: startPos)
    let targetSpanEnd = AbsolutePosition(utf8Offset: startPos + initializerText.utf8.count)
    let targetSpan = targetSpanStart..<targetSpanEnd

    return !TargetNodeFinder.containsNode(
      in: Syntax(parsedScope),
      withSpan: targetSpan,
      matching: initializerText
    )
  }
}

/// A visitor that checks if a syntax node with a matching span and description exists.
private final class TargetNodeFinder: SyntaxAnyVisitor {
  let targetSpan: Range<AbsolutePosition>
  let targetText: String
  var found = false

  init(targetSpan: Range<AbsolutePosition>, targetText: String) {
    self.targetSpan = targetSpan
    self.targetText = targetText
    super.init(viewMode: .sourceAccurate)
  }

  static func containsNode(
    in node: Syntax,
    withSpan span: Range<AbsolutePosition>,
    matching text: String
  ) -> Bool {
    let finder = TargetNodeFinder(targetSpan: span, targetText: text)
    finder.walk(node)
    return finder.found
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if found {
      return .skipChildren
    }

    // Prune subtree traversal if the node does not contain the target span.
    guard node.range.contains(targetSpan) else {
      return .skipChildren
    }

    let nodeStart = node.positionAfterSkippingLeadingTrivia
    let nodeEnd = node.endPositionBeforeTrailingTrivia
    if nodeStart == targetSpan.lowerBound && nodeEnd == targetSpan.upperBound {
      if node.trimmedDescription == targetText {
        found = true
        return .skipChildren
      }
    }

    return .visitChildren
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
      nodeIdentifier == targetIdentifier
    else {
      return .visitChildren
    }

    let lookupResults = node.lookup(nodeIdentifier)
    for result in lookupResults {
      switch result {
      case .fromScope(_, let names):
        let matchesTarget = names.contains { name in
          name.syntax.id == targetBinding.pattern.id
        }
        if matchesTarget {
          candidates.append(node)
        }
        return .visitChildren
      default:
        continue
      }
    }
    return .visitChildren
  }
}
