//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftRefactor
package import SwiftSyntax

/// Describes a "some" parameter that has been rewritten into a generic
/// parameter.
private struct RewrittenSome {
  let original: SomeOrAnyTypeSyntax
  let genericParam: GenericParameterSyntax
  let genericParamRef: IdentifierTypeSyntax
}

/// Rewrite `some` parameters to explicit generic parameters.
///
/// ## Before
///
/// ```swift
/// func someFunction(_ input: some Value) {}
/// ```
///
/// ## After
///
/// ```swift
/// func someFunction<T1: Value>(_ input: T1) {}
/// ```
private class SomeParameterRewriter: SyntaxRewriter {
  var rewrittenSomeParameters: [RewrittenSome] = []

  override func visit(_ node: SomeOrAnyTypeSyntax) -> TypeSyntax {
    if node.someOrAnySpecifier.text != "some" {
      return TypeSyntax(node)
    }

    let paramName = "T\(rewrittenSomeParameters.count + 1)"
    let paramNameSyntax = TokenSyntax.identifier(paramName)

    let inheritedType: TypeSyntax?
    let colon: TokenSyntax?
    if node.constraint.description != "Any" {
      colon = .colonToken()
      inheritedType = node.constraint.with(\.leadingTrivia, .space)
    } else {
      colon = nil
      inheritedType = nil
    }

    let genericParam = GenericParameterSyntax(
      attributes: [],
      specifier: nil,
      name: paramNameSyntax,
      colon: colon,
      inheritedType: inheritedType,
      trailingComma: nil
    )

    let genericParamRef = IdentifierTypeSyntax(
      name: .identifier(paramName),
      genericArgumentClause: nil
    )

    rewrittenSomeParameters.append(
      .init(
        original: node,
        genericParam: genericParam,
        genericParamRef: genericParamRef
      )
    )

    return TypeSyntax(genericParamRef)
  }

  override func visit(_ node: TupleTypeSyntax) -> TypeSyntax {
    let newNode = super.visit(node)

    // If this tuple type is simple parentheses around a replaced "some"
    // parameter, drop the parentheses.
    guard let newTuple = newNode.as(TupleTypeSyntax.self),
      newTuple.elements.count == 1,
      let onlyElement = newTuple.elements.first,
      onlyElement.firstName == nil,
      onlyElement.ellipsis == nil,
      let onlyIdentifierType =
        onlyElement.type.as(IdentifierTypeSyntax.self),
      rewrittenSomeParameters.first(
        where: { $0.genericParamRef.name.text == onlyIdentifierType.name.text }
      ) != nil
    else {
      return newNode
    }

    return TypeSyntax(onlyIdentifierType)
  }
}

/// Rewrite `some` parameters to explicit generic parameters.
///
/// ## Before
///
/// ```swift
/// func someFunction(_ input: some Value) {}
/// ```
///
/// ## After
///
/// ```swift
/// func someFunction<T1: Value>(_ input: T1) {}
/// ```
package struct OpaqueParameterToGeneric: SyntaxRefactoringProvider {
  /// Replace all of the "some" parameters in the given parameter clause with
  /// freshly-created generic parameters.
  ///
  /// - Returns: nil if there was nothing to rewrite, or a pair of the
  /// rewritten parameters and augmented generic parameter list.
  static func replaceSomeParameters(
    in params: FunctionParameterClauseSyntax,
    augmenting genericParams: GenericParameterClauseSyntax?
  ) -> (FunctionParameterClauseSyntax, GenericParameterClauseSyntax)? {
    let rewriter = SomeParameterRewriter(viewMode: .sourceAccurate)
    let rewrittenParams = rewriter.visit(params.parameters)

    if rewriter.rewrittenSomeParameters.isEmpty {
      return nil
    }

    var newGenericParams: [GenericParameterSyntax] = []
    if let genericParams {
      newGenericParams.append(contentsOf: genericParams.parameters)
    }

    for rewritten in rewriter.rewrittenSomeParameters {
      let newGenericParam = rewritten.genericParam

      // Add a trailing comma to the prior generic parameter, if there is one.
      if let lastNewGenericParam = newGenericParams.last {
        newGenericParams[newGenericParams.count - 1] =
          lastNewGenericParam.with(\.trailingComma, .commaToken())
        newGenericParams.append(newGenericParam.with(\.leadingTrivia, .space))
      } else {
        newGenericParams.append(newGenericParam)
      }
    }

    let newGenericParamSyntax = GenericParameterListSyntax(newGenericParams)
    let newGenericParamClause: GenericParameterClauseSyntax
    if let genericParams {
      newGenericParamClause = genericParams.with(
        \.parameters,
        newGenericParamSyntax
      )
    } else {
      newGenericParamClause = GenericParameterClauseSyntax(
        leftAngle: .leftAngleToken(),
        parameters: newGenericParamSyntax,
        genericWhereClause: nil,
        rightAngle: .rightAngleToken()
      )
    }

    return (
      params.with(\.parameters, rewrittenParams),
      newGenericParamClause
    )
  }

  package static func refactor(
    syntax decl: DeclSyntax,
    in context: Void
  ) throws -> DeclSyntax {
    // Function declaration.
    if let funcSyntax = decl.as(FunctionDeclSyntax.self) {
      guard
        let (newInput, newGenericParams) = replaceSomeParameters(
          in: funcSyntax.signature.parameterClause,
          augmenting: funcSyntax.genericParameterClause
        )
      else {
        throw RefactoringNotApplicableError("found no parameters to rewrite")
      }

      return DeclSyntax(
        funcSyntax
          .with(\.signature, funcSyntax.signature.with(\.parameterClause, newInput))
          .with(\.genericParameterClause, newGenericParams)
      )
    }

    // Initializer declaration.
    if let initSyntax = decl.as(InitializerDeclSyntax.self) {
      guard
        let (newInput, newGenericParams) = replaceSomeParameters(
          in: initSyntax.signature.parameterClause,
          augmenting: initSyntax.genericParameterClause
        )
      else {
        throw RefactoringNotApplicableError("found no parameters to rewrite")
      }

      return DeclSyntax(
        initSyntax
          .with(\.signature, initSyntax.signature.with(\.parameterClause, newInput))
          .with(\.genericParameterClause, newGenericParams)
      )
    }

    // Subscript declaration.
    if let subscriptSyntax = decl.as(SubscriptDeclSyntax.self) {
      guard
        let (newIndices, newGenericParams) = replaceSomeParameters(
          in: subscriptSyntax.parameterClause,
          augmenting: subscriptSyntax.genericParameterClause
        )
      else {
        throw RefactoringNotApplicableError("found no parameters to rewrite")
      }

      return DeclSyntax(
        subscriptSyntax
          .with(\.parameterClause, newIndices)
          .with(\.genericParameterClause, newGenericParams)
      )
    }

    throw RefactoringNotApplicableError("unsupported declaration")
  }
}
