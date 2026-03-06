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

/// A code action that adds `@Sendable` to function types for concurrency safety.
///
/// Examples:
/// - `() -> Void` → `@Sendable () -> Void`
/// - `@escaping () -> Void` → `@Sendable @escaping () -> Void`
struct AddSendableAnnotation: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    // Try to find a FunctionTypeSyntax either as a parent or within an
    // AttributedTypeSyntax that contains a function type.
    let functionType: FunctionTypeSyntax
    let attributedType: AttributedTypeSyntax?

    if let ft = node.findParentOfSelf(
      ofType: FunctionTypeSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) }
    ) {
      functionType = ft
      attributedType = ft.parent?.as(AttributedTypeSyntax.self)
    } else if let at = node.findParentOfSelf(
      ofType: AttributedTypeSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) }
    ), let ft = at.baseType.as(FunctionTypeSyntax.self) {
      functionType = ft
      attributedType = at
    } else {
      return []
    }

    // Check if @Sendable is already present.
    if let at = attributedType {
      for attribute in at.attributes {
        if case .attribute(let attr) = attribute,
           attr.attributeName.trimmedDescription == "Sendable" {
          return []
        }
      }
    }

    let sendableAttribute = AttributeSyntax(
      atSign: .atSignToken(),
      attributeName: IdentifierTypeSyntax(name: .identifier("Sendable")),
      trailingTrivia: .space
    )

    let newText: String
    let editRange: Range<Position>

    if let at = attributedType {
      // Already has attributes (e.g., @escaping) — prepend @Sendable before them.
      let newAttributes = AttributeListSyntax(
        [.attribute(sendableAttribute)] + at.attributes.map { $0 }
      )
      let newAttributedType = at.with(\.attributes, newAttributes)
      newText = newAttributedType.trimmedDescription
      editRange = Range(
        uncheckedBounds: (
          lower: scope.snapshot.position(of: at.positionAfterSkippingLeadingTrivia),
          upper: scope.snapshot.position(of: at.endPositionBeforeTrailingTrivia)
        )
      )
    } else {
      // No existing attributes — just prepend @Sendable.
      newText = "@Sendable \(functionType.trimmedDescription)"
      editRange = Range(
        uncheckedBounds: (
          lower: scope.snapshot.position(of: functionType.positionAfterSkippingLeadingTrivia),
          upper: scope.snapshot.position(of: functionType.endPositionBeforeTrailingTrivia)
        )
      )
    }

    return [
      CodeAction(
        title: "Add @Sendable",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: editRange,
                newText: newText
              )
            ]
          ]
        )
      )
    ]
  }
}
