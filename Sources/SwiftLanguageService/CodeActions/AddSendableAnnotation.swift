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
import SwiftRefactor
import SwiftSyntax

/// Code action that adds `@Sendable` to closures and function types for concurrency safety.
///
/// ## Example
/// Before: `func perform(callback: @escaping () -> Void) { ... }`
/// After:  `func perform(callback: @Sendable @escaping () -> Void) { ... }`
package struct AddSendableAnnotation: EditRefactoringProvider {
  static func textRefactor(syntax type: TypeSyntax, in context: Void) -> [SourceEdit] {
    let insertPos = type.position
    return [
      SourceEdit(range: insertPos..<insertPos, replacement: "@Sendable ")
    ]
  }
}

extension AddSendableAnnotation: SyntaxRefactoringCodeActionProvider {
  static var title: String { "Add @Sendable" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    findFunctionTypeToAnnotate(in: scope)
  }
}

/// Walks up from the scope's innermost node to find a function type (or attributed function type)
/// that does not already have @Sendable and returns the type node to edit.
private func findFunctionTypeToAnnotate(in scope: SyntaxCodeActionScope) -> TypeSyntax? {
  scope.innermostNodeContainingRange?.ancestorOrSelf(mapping: { node in
    if let attributed = node.as(AttributedTypeSyntax.self),
       typeIsOrContainsFunctionType(attributed.baseType),
       !attributed.attributes.contains(where: { element in
         guard let attr = element.as(AttributeSyntax.self) else { return false }
         return attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Sendable"
       })
    {
      return TypeSyntax(attributed)
    }
    if let functionType = node.as(FunctionTypeSyntax.self) {
      return TypeSyntax(functionType)
    }
    return nil
  })
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
