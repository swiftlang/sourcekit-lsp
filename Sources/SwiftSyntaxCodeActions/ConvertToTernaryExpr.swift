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

@_spi(SourceKitLSP) package import LanguageServerProtocol
import SourceKitLSP
import SwiftSyntax

/// Converts an `if` statement that assigns the same destination in both branches into a ternary expression.
///
/// If the selection also contains the `let` or `var` declaration preceding the `if`, that declaration is merged into
/// the ternary expression.
package struct ConvertToTernaryExpr: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let items = selectedItems(in: scope) else {
      return []
    }

    let ifExpr: IfExprSyntax
    let bindingDecl: VariableDeclSyntax?
    switch items.count {
    case 1:
      guard let selectedIf = expression(items[0].item)?.as(IfExprSyntax.self) else {
        return []
      }
      ifExpr = selectedIf
      bindingDecl = nil
    case 2:
      guard
        let decl = items[0].item.as(VariableDeclSyntax.self),
        decl.bindings.count == 1,
        let selectedIf = expression(items[1].item)?.as(IfExprSyntax.self)
      else {
        return []
      }
      ifExpr = selectedIf
      bindingDecl = decl
    default:
      return []
    }

    guard
      ifExpr.conditions.count == 1,
      let condition = ifExpr.conditions.first,
      case .expression(let conditionExpr) = condition.condition,
      let elseBody = ifExpr.elseBody,
      case .codeBlock(let elseBlock) = elseBody,
      let thenAssignment = assignment(in: ifExpr.body),
      let elseAssignment = assignment(in: elseBlock),
      isSupportedDestination(thenAssignment.dest),
      isSupportedDestination(elseAssignment.dest),
      thenAssignment.dest.trimmedDescription == elseAssignment.dest.trimmedDescription
    else {
      return []
    }

    if let bindingDecl {
      guard
        let binding = bindingDecl.bindings.first,
        binding.initializer == nil,
        binding.accessorBlock == nil,
        binding.pattern.is(IdentifierPatternSyntax.self) || binding.pattern.is(TuplePatternSyntax.self),
        binding.pattern.trimmedDescription == thenAssignment.dest.trimmedDescription
      else {
        return []
      }
    }

    let conditionText = conditionExpr.trimmedDescription
    let thenText = thenAssignment.value.trimmedDescription
    let elseText = elseAssignment.value.trimmedDescription
    let value = "\(conditionText) ? \(thenText) : \(elseText)"

    let newText: String
    let replaceRange: Range<AbsolutePosition>
    if let bindingDecl {
      newText = "\(bindingDecl.trimmedDescription) = \(value)"
      replaceRange = bindingDecl.positionAfterSkippingLeadingTrivia..<ifExpr.endPositionBeforeTrailingTrivia
    } else {
      newText = "\(thenAssignment.dest.trimmedDescription) = \(value)"
      replaceRange = ifExpr.positionAfterSkippingLeadingTrivia..<ifExpr.endPositionBeforeTrailingTrivia
    }

    let edit = TextEdit(range: scope.snapshot.positionRange(of: replaceRange), newText: newText)
    return [
      CodeAction(
        title: "Convert To Ternary Expression",
        kind: .refactorRewrite,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  /// Returns the statements that are entirely contained in the selected range.
  private static func selectedItems(in scope: SyntaxCodeActionScope) -> [CodeBlockItemSyntax]? {
    guard
      let list = scope.innermostNodeContainingRange?.findParentOfSelf(
        ofType: CodeBlockItemListSyntax.self,
        stoppingIf: { _ in false }
      )
    else {
      return nil
    }
    let items = Array(
      list.filter {
        $0.position >= scope.range.lowerBound && $0.endPosition <= scope.range.upperBound
      }
    )
    return items.isEmpty ? nil : items
  }

  /// Returns the destination and value of the only assignment in `codeBlock`, or `nil` if there isn't exactly one.
  private static func assignment(in codeBlock: CodeBlockSyntax) -> (dest: ExprSyntax, value: ExprSyntax)? {
    guard codeBlock.statements.count == 1, let statement = codeBlock.statements.first else {
      return nil
    }
    return assignment(in: statement.item)
  }

  private static func assignment(in item: CodeBlockItemSyntax.Item) -> (dest: ExprSyntax, value: ExprSyntax)? {
    guard let sequence = expression(item)?.as(SequenceExprSyntax.self) else {
      return nil
    }
    let elements = Array(sequence.elements)
    guard
      elements.count >= 3,
      isAssignmentOperator(elements[1]),
      !elements.dropFirst(2).contains(where: isAssignmentOperator)
    else {
      return nil
    }
    return (
      elements[0],
      ExprSyntax(SequenceExprSyntax(elements: ExprListSyntax(Array(elements.dropFirst(2)))))
    )
  }

  private static func expression(_ item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
    if let expr = item.as(ExprSyntax.self) {
      return expr
    }
    if let statement = item.as(ExpressionStmtSyntax.self) {
      return statement.expression
    }
    return nil
  }

  private static func isAssignmentOperator(_ expr: ExprSyntax) -> Bool {
    return expr.firstToken(viewMode: .sourceAccurate)?.text == "="
  }

  private static func isSupportedDestination(_ expr: ExprSyntax) -> Bool {
    return expr.is(DeclReferenceExprSyntax.self) || expr.is(TupleExprSyntax.self)
  }
}
