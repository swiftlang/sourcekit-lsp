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

/// Syntactic code action provider to convert an if/else statement whose
/// branches assign to the same destination into a ternary expression.
///
/// ## Before
/// ```swift
/// let result: Int
/// if condition {
///   result = computeThen()
/// } else {
///   result = computeElse()
/// }
/// ```
///
/// ## After
/// ```swift
/// let result = condition ? computeThen() : computeElse()
/// ```
///
/// Also converts assignment form:
///
/// ## Before
/// ```swift
/// if condition {
///   result = computeThen()
/// } else {
///   result = computeElse()
/// }
/// ```
///
/// ## After
/// ```swift
/// result = condition ? computeThen() : computeElse()
/// ```
@_spi(Testing) public struct ConvertToTernaryExpr: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let info = findConvertibleIfStatement(in: scope) else {
      return []
    }

    let condition = info.condition.trimmedDescription
    let thenValue = info.thenValue.trimmedDescription
    let elseValue = info.elseValue.trimmedDescription

    var replacementText: String
    if let binding = info.binding {
      // `let result` + assignments in both branches: fold the binding into
      // a single `let` with a ternary initializer (the initializer runs
      // exactly once, so `let` stays sound).
      let pattern = binding.pattern.trimmedDescription
      replacementText = "let \(pattern) = \(condition) ? \(thenValue) : \(elseValue)"
    } else if let destination = info.destination {
      let dest = destination.trimmedDescription
      replacementText = "\(dest) = \(condition) ? \(thenValue) : \(elseValue)"
    } else {
      return []
    }

    // Replace from the start of the whole if statement (or its variable
    // declaration, if we consumed a separate binding) through the end of
    // the if statement.
    let startNode = info.binding.map { Syntax($0) } ?? Syntax(info.ifStmt)
    let edit = TextEdit(
      range: scope.snapshot.positionRange(
        of: startNode.positionAfterSkippingLeadingTrivia
          ..< info.ifStmt.endPosition
      ),
      newText: replacementText
    )

    return [
      CodeAction(
        title: "Convert to ternary expression",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  struct ConvertibleInfo {
    /// The `if` statement to replace.
    let ifStmt: IfExprSyntax
    /// A variable declaration binding that precedes the `if` (e.g.
    /// `let result: Int`), which the ternary initializer replaces.
    let binding: PatternBindingSyntax?
    /// The destination assigned in both branches (absent when `binding`
    /// is present, where the pattern is the destination).
    let destination: ExprSyntax?
    /// The if condition expression.
    let condition: ExprSyntax
    /// Value assigned in the then-branch.
    let thenValue: ExprSyntax
    /// Value assigned in the else-branch.
    let elseValue: ExprSyntax
  }

  /// Walks up from the cursor to find an if statement convertible to a
  /// ternary, optionally consuming a preceding uninitialized variable
  /// declaration (`let result: Int`).
  static func findConvertibleIfStatement(
    in scope: SyntaxCodeActionScope
  ) -> ConvertibleInfo? {
    guard let innermost = scope.innermostNodeContainingRange else {
      return nil
    }

    var node: Syntax? = Syntax(innermost)
    while let current = node {
      if let ifStmt = current.as(IfExprSyntax.self) {
        return convertibleInfo(for: ifStmt)
      }
      // The cursor might sit on a brace or a boundary token: innermost may
      // be the then-block of the target if, or the enclosing block.
      if let codeBlock = current.as(CodeBlockSyntax.self) {
        // The block itself is the then-branch of an if? (cursor on the
        // open/close brace or on the boundary after the condition)
        if let ifStmt = current.parent?.as(IfExprSyntax.self) {
          return convertibleInfo(for: ifStmt)
        }
        return convertibleIfAmongSiblings(of: Syntax(codeBlock))
      }
      if current.is(MemberBlockSyntax.self) {
        return convertibleIfAmongSiblings(of: current)
      }
      node = current.parent
    }
    return nil
  }

  /// When the innermost node containing the range is a code block (e.g. the
  /// cursor sits on a brace or empty line), look at the if statements that
  /// are children of that block, including ones preceded by an
  /// uninitialized variable declaration.
  static func convertibleIfAmongSiblings(of block: Syntax) -> ConvertibleInfo? {
    guard let codeBlock = block.as(CodeBlockSyntax.self) else {
      return nil
    }
    let items = Array(codeBlock.statements)
    for (idx, item) in items.enumerated() {
      if let ifStmt = item.item.as(IfExprSyntax.self) {
        return convertibleInfo(for: ifStmt)
      }
      // `let result: Int` immediately followed by the convertible `if`:
      // the cursor on the declaration should still offer the action.
      if let variableDecl = item.item.as(VariableDeclSyntax.self),
        idx + 1 < items.count,
        let ifStmt = items[idx + 1].item.as(IfExprSyntax.self)
      {
        return convertibleInfo(for: ifStmt, precedingBinding: variableDecl)
      }
    }
    return nil
  }

  /// Checks whether an if statement is convertible to a ternary expression
  /// and gathers the pieces of the conversion.
  static func convertibleInfo(
    for ifStmt: IfExprSyntax,
    precedingBinding: VariableDeclSyntax? = nil
  ) -> ConvertibleInfo? {
    // Exactly one plain expression condition. Depending on parse context,
    // the condition is either an expression directly or an
    // ExpressionPatternSyntax wrapped in a ConditionElementSyntax.
    guard ifStmt.conditions.count == 1,
      let conditionElement = ifStmt.conditions.first
    else {
      return nil
    }
    let condition = conditionElement.condition.as(ExprSyntax.self)
    guard let condition else {
      return nil
    }

    // The branches must be plain code blocks.
    let thenBlock = ifStmt.body
    guard case .codeBlock(let elseBlock)? = ifStmt.elseBody else {
      return nil
    }

    // Each branch must consist of exactly one assignment statement.
    guard thenBlock.statements.count == 1, elseBlock.statements.count == 1,
      let thenSequence = thenBlock.statements.first?.item.as(SequenceExprSyntax.self),
      let elseSequence = elseBlock.statements.first?.item.as(SequenceExprSyntax.self)
    else {
      return nil
    }

    // `x = y` parses as a SequenceExpr of [x, =, y].
    let thenElements = Array(thenSequence.elements)
    let elseElements = Array(elseSequence.elements)
    guard thenElements.count == 3, elseElements.count == 3,
      thenElements[1].is(AssignmentExprSyntax.self),
      elseElements[1].is(AssignmentExprSyntax.self)
    else {
      return nil
    }
    let thenDest = thenElements[0]
    let elseDest = elseElements[0]

    // The destinations must be textually identical (same name/path).
    guard thenDest.trimmedDescription == elseDest.trimmedDescription else {
      return nil
    }

    if let binding = precedingBinding {
      // The binding must declare exactly the assigned name, uninitialized.
      guard let firstBinding = binding.bindings.first,
        binding.bindings.count == 1,
        firstBinding.initializer == nil,
        firstBinding.accessorBlock == nil,
        firstBinding.pattern.trimmedDescription == thenDest.trimmedDescription
      else {
        return nil
      }
      return ConvertibleInfo(
        ifStmt: ifStmt,
        binding: firstBinding,
        destination: nil,
        condition: condition,
        thenValue: thenElements[2],
        elseValue: elseElements[2]
      )
    }

    return ConvertibleInfo(
      ifStmt: ifStmt,
      binding: nil,
      destination: thenDest,
      condition: condition,
      thenValue: thenElements[2],
      elseValue: elseElements[2]
    )
  }
}
