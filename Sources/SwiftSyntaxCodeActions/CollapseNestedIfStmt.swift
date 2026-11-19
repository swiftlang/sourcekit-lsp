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

/// Syntactic code action provider to collapse a nested if statement with
/// no else clauses into a single if with multiple conditions.
///
/// ## Before
/// ```swift
/// if a {
///   if b {
///     doWork()
///   }
/// }
/// ```
///
/// ## After
/// ```swift
/// if a, b {
///   doWork()
/// }
/// ```
@_spi(Testing) public struct CollapseNestedIfStmt: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let info = findCollapsibleNestedIf(in: scope) else {
      return []
    }

    let outerConditions = info.outerIf.conditions.trimmedDescription
    let innerConditions = info.innerIf.conditions.trimmedDescription

    // Replace the outer if with the merged form. Re-indent the inner body
    // by stripping the inner if's base indentation and applying the outer
    // if's base indentation.
    let baseIndentation = Trivia(
      pieces: info.outerIf.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    ).description
    let innerIndentation = Trivia(
      pieces: info.innerIf.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    ).description

    let bodyLines = info.innerIf.body.description
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    var trimmed = bodyLines
    if let last = trimmed.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
      trimmed.removeLast()
    }
    let indented = trimmed.enumerated().map { (i, line) -> String in
      if i == 0 || line.isEmpty {
        return line
      }
      var line = Substring(line)
      if line.hasPrefix(innerIndentation) {
        line = line.dropFirst(innerIndentation.count)
      }
      return baseIndentation + line
    }.joined(separator: "\n")

    let replacementText = "if \(outerConditions), \(innerConditions) \(indented)"

    let edit = TextEdit(
      range: scope.snapshot.positionRange(
        of: info.outerIf.positionAfterSkippingLeadingTrivia
          ..< info.outerIf.endPosition
      ),
      newText: replacementText
    )

    return [
      CodeAction(
        title: "Collapse nested if statements",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  /// The two if statements to merge.
  struct CollapsibleInfo {
    let outerIf: IfExprSyntax
    let innerIf: IfExprSyntax
  }

  /// Finds an outer `if` without else whose body is exactly one inner `if`
  /// without else.
  static func findCollapsibleNestedIf(
    in scope: SyntaxCodeActionScope
  ) -> CollapsibleInfo? {
    guard let innermost = scope.innermostNodeContainingRange else {
      return nil
    }

    var node: Syntax? = Syntax(innermost)
    while let current = node {
        if let ifStmt = current.as(IfExprSyntax.self) {
        if let info = collapsibleInfo(for: ifStmt) {
          return info
        }
        // Cursor on the inner if: its enclosing code block may be the sole
        // body of an outer if that is itself collapsible.
        var enclosing: Syntax? = current.parent
        // Unwrap ExpressionStmtSyntax and its CodeBlockItemSyntax wrapper.
        if let exprStmt = enclosing?.as(ExpressionStmtSyntax.self) {
          enclosing = exprStmt.parent
        }
        if let item = enclosing?.as(CodeBlockItemSyntax.self) {
          enclosing = item.parent
        }
        if let list = enclosing?.as(CodeBlockItemListSyntax.self) {
          enclosing = list.parent
        }
        if let block = enclosing?.as(CodeBlockSyntax.self),
          let outerIf = block.parent?.as(IfExprSyntax.self),
          let info = collapsibleInfo(for: outerIf)
        {
          return info
        }
        return nil
      }
      if let codeBlock = current.as(CodeBlockSyntax.self) {
        // The cursor may sit on the outer if's brace or inside its body:
        // check whether the block is an outer if's then-branch.
        if let ifStmt = current.parent?.as(IfExprSyntax.self) {
          return collapsibleInfo(for: ifStmt)
        }
        // Otherwise look for a top-level if among the block's children.
        for item in codeBlock.statements {
          if let ifStmt = item.item.as(IfExprSyntax.self) {
            return collapsibleInfo(for: ifStmt)
          }
        }
        return nil
      }
      node = current.parent
    }
    return nil
  }

  /// Checks whether an if statement is collapsible: no else clause, body
  /// is exactly one if statement that itself has no else clause.
  static func collapsibleInfo(for outerIf: IfExprSyntax) -> CollapsibleInfo? {
    // Neither if may have an else clause.
    guard outerIf.elseBody == nil else {
      return nil
    }

    // The body must be exactly one statement which is an if. Depending on
    // the parse context the if may be wrapped in an ExpressionStmtSyntax.
    let singleItem = outerIf.body.statements.first?.item
    let unwrapped: (any SyntaxProtocol)?
    if let exprStmt = singleItem?.as(ExpressionStmtSyntax.self) {
      unwrapped = exprStmt.expression
    } else {
      unwrapped = singleItem
    }
    guard outerIf.body.statements.count == 1,
      let innerIf = unwrapped?.as(IfExprSyntax.self)
    else {
      return nil
    }

    guard innerIf.elseBody == nil else {
      return nil
    }

    return CollapsibleInfo(outerIf: outerIf, innerIf: innerIf)
  }
}
