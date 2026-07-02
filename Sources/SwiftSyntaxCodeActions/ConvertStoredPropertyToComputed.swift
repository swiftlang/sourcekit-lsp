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

import SwiftRefactor
package import SwiftSyntax
import SwiftSyntaxBuilder

package struct ConvertStoredPropertyToComputed: SyntaxRefactoringProvider {
  package struct Context {
    package let type: TypeSyntax?

    package init(type: TypeSyntax? = nil) {
      self.type = type
    }
  }
  package static func refactor(syntax: VariableDeclSyntax, in context: Context) throws -> VariableDeclSyntax {
    guard syntax.bindings.count == 1, let binding = syntax.bindings.first, let initializer = binding.initializer else {
      throw RefactoringNotApplicableError("unsupported variable declaration")
    }

    var syntax = syntax

    if let lazyKeyword = syntax.modifiers.first(where: { $0.name.tokenKind == .keyword(.lazy) }) {
      syntax = DeclModifierRemover { $0.id == lazyKeyword.id }
        .rewrite(syntax)
        .cast(VariableDeclSyntax.self)
    }

    var codeBlockSyntax: CodeBlockItemListSyntax

    if let functionExpression = initializer.value.as(FunctionCallExprSyntax.self),
      let closureExpression = functionExpression.calledExpression.as(ClosureExprSyntax.self)
    {
      guard functionExpression.arguments.isEmpty else {
        throw RefactoringNotApplicableError(
          "initializer is a closure that takes arguments"
        )
      }

      codeBlockSyntax = closureExpression.statements
      codeBlockSyntax.leadingTrivia =
        closureExpression.leftBrace.leadingTrivia + closureExpression.leftBrace.trailingTrivia
        + codeBlockSyntax.leadingTrivia
      codeBlockSyntax.trailingTrivia +=
        closureExpression.trailingTrivia + closureExpression.rightBrace.leadingTrivia
        + closureExpression.rightBrace.trailingTrivia + functionExpression.trailingTrivia
    } else {
      var body = CodeBlockItemListSyntax([
        CodeBlockItemSyntax(
          item: .expr(initializer.value)
        )
      ])
      body.leadingTrivia = initializer.equal.trailingTrivia + body.leadingTrivia
      body.trailingTrivia += .space
      codeBlockSyntax = body
    }
    let typeAnnotation: TypeAnnotationSyntax?
    if let existingType = binding.typeAnnotation {
      typeAnnotation = existingType
    } else if let providedType = context.type {
      typeAnnotation = TypeAnnotationSyntax(
        colon: .colonToken(trailingTrivia: .space),
        type: providedType
      )
    } else {
      typeAnnotation = TypeAnnotationSyntax(
        colon: .colonToken(trailingTrivia: .space),
        type: TypeSyntax(stringLiteral: "<#Type#>")
      )
    }

    let newBinding =
      binding
      .with(\.pattern, binding.pattern.with(\.trailingTrivia, []))
      .with(\.initializer, nil)
      .with(\.typeAnnotation, typeAnnotation)
      .with(
        \.accessorBlock,
        AccessorBlockSyntax(
          accessors: .getter(codeBlockSyntax)
        )
      )

    let newBindingSpecifier =
      syntax.bindingSpecifier
      .with(\.tokenKind, .keyword(.var))

    return
      syntax
      .with(\.bindingSpecifier, newBindingSpecifier)
      .with(\.bindings, PatternBindingListSyntax([newBinding]))
  }
}
