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

package import LanguageServerProtocol
import SourceKitLSP
import SwiftRefactor
package import SwiftSyntax
import SwiftSyntaxBuilder
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

package struct ConvertStoredPropertyToComputed: SyntaxRefactoringProvider, ResolvableSyntaxRefactoringCodeActionProvider
{
  package typealias Input = VariableDeclSyntax

  static let title: String = "Convert Stored Property to Computed Property"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> VariableDeclSyntax? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: VariableDeclSyntax.self,
      stoppingIf: {
        $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) || $0.is(InitializerClauseSyntax.self)
      }
    )
  }

  package struct Context {
    package let type: TypeSyntax?

    package init(type: TypeSyntax? = nil) {
      self.type = type
    }
  }

  package struct UnresolvedData: Codable, LSPAnyCodable {
    package let position: Position
  }

  static func refactoringContext(
    for node: Input,
    in scope: SyntaxCodeActionScope
  ) -> RefactoringContext<Context, UnresolvedData> {
    guard scope.resolveSupport?.canResolveEdit ?? false else {
      // If the editor doesn't have resolve support, fall back to a syntactic action that introduces an editor placeholder for the type, similar to
      // if the type cannot be inferred.
      return .context(Context())
    }
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
    return .unresolved(UnresolvedData(position: scope.snapshot.position(of: identifier.position)))
  }

  static func resolveContext(
    for data: UnresolvedData,
    in scope: SyntaxCodeActionScope,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> Context {
    guard let symbolInfo = try await symbolInfo(data.position).only, let typeName = symbolInfo.typeName, typeName != "_"
    else {
      return Context()
    }
    return Context(type: "\(raw: typeName)")
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
