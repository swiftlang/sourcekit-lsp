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
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SourceKitLSP
import SwiftBasicFormat
import SwiftExtensions
import SwiftSyntax
import SwiftSyntaxBuilder

/// Syntactic code action provider to expand a ternary expression that
/// assigns to a destination into an if/else statement.
///
/// ## Before
/// ```swift
/// result = condition ? computeThen() : computeElse()
/// ```
///
/// ## After
/// ```swift
/// if condition {
///   result = computeThen()
/// } else {
///   result = computeElse()
/// }
/// ```
///
/// Also expands a variable binding initialized with a ternary:
///
/// ## Before
/// ```swift
/// let result = condition ? a() : b()
/// ```
///
/// ## After
/// ```swift
/// let result: <type>
/// if condition {
///   result = a()
/// } else {
///   result = b()
/// }
/// ```
///
/// For binding expansion the declared type is reused when written
/// explicitly; when the binding has no written type, the action is not
/// offered (inferring the type would require semantic information).
@_spi(Testing) public struct ExpandTernaryExpr: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let info = findExpandableTernary(in: scope) else {
      return []
    }

    let condition = info.condition.trimmedDescription
    let thenValue = info.thenValue.trimmedDescription
    let elseValue = info.elseValue.trimmedDescription
    let dest = info.destination

    var replacementText: String
    if let typeAnnotation = info.typeAnnotation {
      // `let x: T = ternary` → declare uninitialized, then assign. The
      // replacement starts after the `let` keyword of the binding.
      replacementText = """
      \(dest)\(typeAnnotation)
      if \(condition) {
          \(dest) = \(thenValue)
      } else {
          \(dest) = \(elseValue)
      }
      """
    } else {
      replacementText = """
      if \(condition) {
          \(dest) = \(thenValue)
      } else {
          \(dest) = \(elseValue)
      }
      """
    }

    // Replace the ternary statement (or the whole binding) from the start
    // of the statement to its end.
    let edit = TextEdit(
      range: scope.snapshot.positionRange(
        of: info.statementStart.positionAfterSkippingLeadingTrivia
          ..< info.statementEnd.endPosition
      ),
      newText: replacementText
    )

    return [
      CodeAction(
        title: "Expand ternary expression",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  struct ExpandableInfo {
    /// Assignment destination (also used as the binding pattern name).
    let destination: String
    /// The ternary condition expression.
    let condition: ExprSyntax
    /// Value produced in the then-branch.
    let thenValue: ExprSyntax
    /// Value produced in the else-branch.
    let elseValue: ExprSyntax
    /// Written type annotation for binding form (`: Int`), if present.
    let typeAnnotation: String?
    /// Start of the region to replace (binding node if present, else the
    /// expression statement).
    let statementStart: any SyntaxProtocol
    /// End of the region to replace.
    let statementEnd: any SyntaxProtocol
  }

  /// Walks up from the cursor to find a ternary expression in an
  /// assignment (`x = c ? a : b`) or a binding initializer
  /// (`let x = c ? a : b`).
  static func findExpandableTernary(
    in scope: SyntaxCodeActionScope
  ) -> ExpandableInfo? {
    guard let innermost = scope.innermostNodeContainingRange else {
      return nil
    }

    // Find the ternary sequence the cursor is within, stopping at
    // statement boundaries so we don't grab a ternary from an outer
    // expression.
    var node: Syntax? = Syntax(innermost)
    while let current = node {
      if let sequence = current.as(SequenceExprSyntax.self) {
        if let info = expandableInfo(from: sequence) {
          return info
        }
      }
      if current.is(CodeBlockItemSyntax.self) || current.is(MemberBlockItemSyntax.self) {
        // Statement boundary: last chance — the item itself may directly
        // wrap the sequence.
        if let item = current.as(CodeBlockItemSyntax.self),
          let sequence = item.item.as(SequenceExprSyntax.self),
          let info = expandableInfo(from: sequence)
        {
          return info
        }
        break
      }
      node = current.parent
    }
    return nil
  }

  /// Binding form: the sequence is the initializer of `let x: T`. The
  /// ternary components come straight from the sequence (no `=` inside).
  static func bindingExpandableInfo(
    from sequence: SequenceExprSyntax
  ) -> ExpandableInfo? {
    let elements = Array(sequence.elements)
    // Unfolded: [cond, ?, then, :, else] = 5; folded: [TernaryExpr] = 1.
    var condition: ExprSyntax?
    var thenValue: ExprSyntax?
    var elseValue: ExprSyntax?

    if elements.count == 1, let ternary = elements[0].as(TernaryExprSyntax.self) {
      condition = ternary.condition
      thenValue = ternary.thenExpression
      elseValue = ternary.elseExpression
    } else if elements.count == 3,
      elements[1].is(UnresolvedTernaryExprSyntax.self),
      let cond = ExprSyntax(elements[0]),
      let elseExpr = ExprSyntax(elements[2])
    {
      condition = cond
      thenValue = elements[1].as(UnresolvedTernaryExprSyntax.self)?.thenExpression
      elseValue = elseExpr
    } else {
      return nil
    }

    guard condition != nil, thenValue != nil, elseValue != nil else {
      return nil
    }

    // Must be the initializer of a binding with a written type.
    var parent: Syntax? = Syntax(sequence)
    while let p = parent {
      if let initializer = p.as(InitializerClauseSyntax.self),
        let binding = p.parent?.as(PatternBindingSyntax.self)
      {
        guard initializer.value.id == sequence.id,
          let typeAnnotationNode = binding.typeAnnotation
        else {
          return nil
        }
        guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
          return nil
        }
        return ExpandableInfo(
          destination: pattern.identifier.text,
          condition: condition!,
          thenValue: thenValue!,
          elseValue: elseValue!,
          typeAnnotation: typeAnnotationNode.description
            .trimmingCharacters(in: .whitespacesAndNewlines),
          statementStart: binding,
          statementEnd: binding
        )
      }
      if p.is(CodeBlockItemSyntax.self) {
        return nil
      }
      parent = p.parent
    }
    return nil
  }

  /// Checks whether a sequence expression is `dest = cond ? then : else`
  /// (or the initializer of a binding) and gathers the pieces.
  static func expandableInfo(
    from sequence: SequenceExprSyntax
  ) -> ExpandableInfo? {
    let elements = Array(sequence.elements)

    // Binding form: `let x: T = <ternary>` — the sequence IS the ternary
    // (no assignment element) and lives inside the binding's initializer.
    if let bindingInfo = bindingExpandableInfo(from: sequence) {
      return bindingInfo
    }

    guard elements.count >= 3,
      let assignIndex = elements.firstIndex(where: { $0.is(AssignmentExprSyntax.self) }),
      assignIndex > 0
    else {
      return nil
    }

    let dest = elements[0]

    // The ternary is everything after the `=`. Before operator folding it
    // appears as [cond, UnresolvedTernaryExpr(? then : else)]; after
    // folding as a single TernaryExprSyntax.
    let rhs = Array(elements[(elements.index(after: assignIndex))...])
    var condition: ExprSyntax?
    var thenValue: ExprSyntax?
    var elseValue: ExprSyntax?

    if rhs.count == 1, let ternary = rhs[0].as(TernaryExprSyntax.self) {
      // Folded form: `= cond ? a : b` as a single ternary.
      condition = ternary.condition
      thenValue = ternary.thenExpression
      elseValue = ternary.elseExpression
    } else if rhs.count == 3, let unresolved = rhs[1].as(UnresolvedTernaryExprSyntax.self) {
      // Unfolded parse: `= cond ? then : else` with the `? then :`
      // collected into an UnresolvedTernaryExpr and the else beside it.
      condition = ExprSyntax(rhs[0])
      thenValue = unresolved.thenExpression
      elseValue = ExprSyntax(rhs[2])
    }

    guard let condition, let thenValue, let elseValue else {
      return nil
    }

    // Form 2: `let x = cond ? a : b` — the assignment is inside the
    // binding's initializer. Validate the shape.
    var typeAnnotation: String? = nil
    var statementStart: any SyntaxProtocol = Syntax(sequence)
    var statementEnd: any SyntaxProtocol = sequence

    // Walk up: SequenceExpr → ExpressionStmt/CodeBlockItem, or initializer
    // of a PatternBinding.
    var parent: Syntax? = Syntax(sequence)
    while let p = parent {
      if let initializer = p.as(InitializerClauseSyntax.self),
        let binding = p.parent?.as(PatternBindingSyntax.self)
      {
        // Only accept when the ternary IS the initializer (single
        // element, not part of a larger expression).
        guard initializer.value.id == sequence.id else {
          break
        }
        guard let typeAnnotationNode = binding.typeAnnotation else {
          // No written type: expanding would change the binding into an
          // uninitialized declaration, which requires a written type.
          return nil
        }
        typeAnnotation = typeAnnotationNode.description
          .trimmingCharacters(in: .whitespacesAndNewlines)
        statementStart = binding
        statementEnd = binding
        break
      }
      if p.is(CodeBlockItemSyntax.self) || p.is(MemberBlockItemSyntax.self) {
        if let item = p.as(CodeBlockItemSyntax.self), item.item.id == sequence.id {
          statementStart = item.item
          statementEnd = item.item
        }
        break
      }
      parent = p.parent
    }

    return ExpandableInfo(
      destination: dest.trimmedDescription,
      condition: condition,
      thenValue: thenValue,
      elseValue: elseValue,
      typeAnnotation: typeAnnotation,
      statementStart: statementStart,
      statementEnd: statementEnd
    )
  }
}
