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
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftExtensions
@_spi(Experimental) import SwiftLexicalLookup
import SwiftRefactor
import SwiftSyntax

/// Syntactic code action provider that replaces an unused parameter with `_` across
/// any function or initializer declaration.
struct RemoveUnusedParameter: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let parameter = findParameter(in: scope) else {
      return []
    }

    let firstName = parameter.firstName
    let secondName = parameter.secondName
    let parameterNameToken = secondName ?? firstName
    guard parameterNameToken.tokenKind != .wildcard else {
      return []
    }

    let parameterName = parameterNameToken.text
    guard !parameterName.isEmpty else {
      return []
    }

    guard let parameterList = parameter.parent?.as(FunctionParameterListSyntax.self),
      let parameterClause = parameterList.parent?.as(FunctionParameterClauseSyntax.self),
      let signature = parameterClause.parent?.as(FunctionSignatureSyntax.self)
    else {
      return []
    }

    let body: CodeBlockSyntax?
    if let fn = signature.parent?.as(FunctionDeclSyntax.self) {
      body = fn.body
    } else if let initDecl = signature.parent?.as(InitializerDeclSyntax.self) {
      body = initDecl.body
    } else {
      return []
    }

    guard let body else {
      return []
    }

    guard let targetIdentifier = Identifier(parameterNameToken) else {
      return []
    }

    // Verify the parameter is not used in the body using SwiftLexicalLookup to account for shadowing.
    let usageFinder = ParameterUsageFinder(
      targetIdentifier: targetIdentifier,
      targetParameterId: parameter.id
    )
    usageFinder.walk(Syntax(body))
    guard !usageFinder.isUsed else {
      return []
    }

    guard let replaceAction = replaceUnusedParameterWithWildcard(parameter: parameter, in: scope) else {
      return []
    }

    return [replaceAction]
  }

  // MARK: - Finding target parameter

  private static func findParameter(in scope: SyntaxCodeActionScope) -> FunctionParameterSyntax? {
    guard let node = scope.innermostNodeContainingRange else {
      return nil
    }

    if let param = node.findParentOfSelf(
      ofType: FunctionParameterSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    ) {
      return param
    }

    let parameterClause = node.findParentOfSelf(
      ofType: FunctionParameterClauseSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )

    if let parameterClause {
      let requestedStart = scope.snapshot.absolutePosition(of: scope.requestedRange.lowerBound)
      for param in parameterClause.parameters {
        if requestedStart >= param.position && requestedStart <= param.endPosition {
          return param
        }
      }
    }

    return nil
  }

  // MARK: - Replace with '_' action

  private static func replaceUnusedParameterWithWildcard(
    parameter: FunctionParameterSyntax,
    in scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    let firstName = parameter.firstName
    let secondName = parameter.secondName
    let parameterName = (secondName ?? firstName).text

    let newParam: FunctionParameterSyntax
    if firstName.tokenKind == .wildcard, secondName != nil {
      newParam =
        parameter
        .with(\.firstName, .wildcardToken(leadingTrivia: firstName.leadingTrivia, trailingTrivia: []))
        .with(\.secondName, nil)
    } else if let second = secondName {
      newParam =
        parameter
        .with(\.secondName, .wildcardToken(leadingTrivia: second.leadingTrivia, trailingTrivia: second.trailingTrivia))
    } else {
      newParam =
        parameter
        .with(\.secondName, .wildcardToken(leadingTrivia: .space))
    }

    let edit = SourceEdit(range: parameter.range, replacement: newParam.description)
    guard let workspaceEdit = [edit].asWorkspaceEdit(snapshot: scope.snapshot) else {
      return nil
    }

    return CodeAction(
      title: "Replace unused parameter '\(parameterName)' with '_'",
      kind: .refactorInline,
      edit: workspaceEdit
    )
  }
}

// MARK: - AST Visitors

private final class ParameterUsageFinder: SyntaxVisitor {
  let targetIdentifier: Identifier
  let targetParameterId: SyntaxIdentifier
  var isUsed = false

  init(targetIdentifier: Identifier, targetParameterId: SyntaxIdentifier) {
    self.targetIdentifier = targetIdentifier
    self.targetParameterId = targetParameterId
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if isUsed {
      return .skipChildren
    }

    guard let nodeIdentifier = Identifier(node.baseName),
      nodeIdentifier == targetIdentifier
    else {
      return .visitChildren
    }

    let lookupResults = node.lookup(nodeIdentifier)
    for result in lookupResults {
      switch result {
      case .fromScope(_, let names):
        guard !names.isEmpty else { continue }
        if names.contains(where: { $0.syntax.id == targetParameterId }) {
          isUsed = true
          return .skipChildren
        } else {
          // The identifier resolves to another declaration in an inner scope, shadowing the parameter.
          return .visitChildren
        }
      default:
        continue
      }
    }
    return .visitChildren
  }
}
