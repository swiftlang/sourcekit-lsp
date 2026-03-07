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
import SwiftSyntax

/// Code action that adds `@Sendable` to closures and function types for concurrency safety.
///
/// ## Example
/// Before: `func perform(callback: @escaping () -> Void) { ... }`
/// After:  `func perform(callback: @Sendable @escaping () -> Void) { ... }`
struct AddSendableAnnotation: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let target = findFunctionTypeToAnnotate(in: scope) else {
      return []
    }

    let range = scope.snapshot.range(of: target.type)
    // Insert "@Sendable " at the start of the type so we get e.g. "@Sendable @escaping () -> Void"
    let edit = TextEdit(range: range.lowerBound..<range.lowerBound, newText: "@Sendable ")

    return [
      CodeAction(
        title: "Add @Sendable",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [edit]
          ]
        )
      )
    ]
  }
}

/// A type node (function type or attributed function type) that can have @Sendable added.
private struct SendableAnnotationTarget {
  let type: TypeSyntax
}

/// Walks up from the scope's innermost node to find a function type (or attributed function type)
/// that does not already have @Sendable and returns the type node to edit.
private func findFunctionTypeToAnnotate(in scope: SyntaxCodeActionScope) -> SendableAnnotationTarget? {
  var node: Syntax? = scope.innermostNodeContainingRange
  while let current = node, !current.is(CodeBlockSyntax.self), !current.is(MemberBlockSyntax.self) {
    if let attributed = current.as(AttributedTypeSyntax.self),
       typeIsOrContainsFunctionType(attributed.baseType),
       !attributedTypeHasSendable(attributed)
    {
      return SendableAnnotationTarget(type: TypeSyntax(attributed))
    }
    if let functionType = current.as(FunctionTypeSyntax.self) {
      return SendableAnnotationTarget(type: TypeSyntax(functionType))
    }
    node = current.parent
  }
  return nil
}

private func typeIsOrContainsFunctionType(_ type: TypeSyntax) -> Bool {
  if type.is(FunctionTypeSyntax.self) {
    return true
  }
  if let attributed = type.as(AttributedTypeSyntax.self) {
    return typeIsOrContainsFunctionType(attributed.baseType)
  }
  return false
}

private func attributedTypeHasSendable(_ attributed: AttributedTypeSyntax) -> Bool {
  attributed.attributes.contains { element in
    guard let attr = element.as(AttributeSyntax.self) else { return false }
    return attributeNameIsSendable(attr.attributeName)
  }
}

private func attributeNameIsSendable(_ attributeName: TypeSyntax) -> Bool {
  guard let identifier = attributeName.as(IdentifierTypeSyntax.self) else {
    return false
  }
  return identifier.name.text == "Sendable"
}
