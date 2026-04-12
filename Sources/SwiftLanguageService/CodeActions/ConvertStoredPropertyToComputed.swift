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
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder

extension ConvertStoredPropertyToComputed: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard
      let variableDecl = scope.innermostNodeContainingRange?.as(VariableDeclSyntax.self)
        ?? scope.innermostNodeContainingRange?.parent?.as(VariableDeclSyntax.self)
    else { return [] }

    if variableDecl.bindings.first?.typeAnnotation?.type != nil {
      let context = ConvertStoredPropertyToComputed.Context()
      guard let refactored = try? Self.refactor(syntax: variableDecl, in: context) else { return [] }

      let declRange = scope.snapshot.range(of: variableDecl)
      let edit = TextEdit(
        range: declRange,
        newText: refactored.description
      )

      return [
        CodeAction(
          title: "Convert Stored Property to Computed Property",
          kind: .refactorInline,
          edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
        )
      ]
    }

    return [
      CodeAction(
        title: "Convert Stored Property to Computed Property",
        kind: .refactorInline,
        data: .dictionary([
          "action": .string("Convert Stored Property to Computed Property"),
          "uri": .string(scope.snapshot.uri.stringValue),
          "offset": .int(scope.range.lowerBound.utf8Offset),
        ])
      )
    ]
  }
}
