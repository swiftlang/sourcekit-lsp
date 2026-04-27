//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftExtensions
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder

extension ConvertStoredPropertyToComputed: SyntaxRefactoringCodeActionProvider {
  static let title: String = "Convert Stored Property to Computed Property"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> VariableDeclSyntax? {
    return scope.innermostNodeContainingRange?.as(VariableDeclSyntax.self)
      ?? scope.innermostNodeContainingRange?.parent?.as(VariableDeclSyntax.self)
  }

  static func refactoringContext(
    for node: VariableDeclSyntax,
    in scope: SyntaxCodeActionScope
  ) async -> SyntaxCodeActionContextResult<Context> {
    guard node.bindings.contains(where: { $0.typeAnnotation?.type == nil }) else {
      // All types are syntactically specified, we don't need to resolve the semantic type
      return .context(Context())
    }
    guard let binding = node.bindings.only,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
    else {
      // We can only resolve type information for a single variable binding at the moment. If this is variable decl with multiple bindings, still
      // offer the refactoring action and introduce placeholders for the type annotation.
      return .context(Context())
    }
    if scope.resolveSupport?.canResolveEdit ?? false {
      return .resolveEditLazily
    }
    // Cursor info reports type as `_` if it cannot determine the type.
    if let type = try? await scope.cursorInfo(at: scope.snapshot.position(of: identifier.position)).only?.typeName,
      type != "_"
    {
      return .context(Context(type: "\(raw: type)"))
    }
    return .context(Context())
  }
}
