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

/// Syntactic code action provider that:
/// - Replaces an unused parameter with `_` across any function or initializer declaration.
/// - Removes an unused parameter and updates all call sites for local/nested functions where
///   all call sites are within the same lexical scope.
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
    let functionDecl: FunctionDeclSyntax?
    if let fn = signature.parent?.as(FunctionDeclSyntax.self) {
      body = fn.body
      functionDecl = fn
    } else if let initDecl = signature.parent?.as(InitializerDeclSyntax.self) {
      body = initDecl.body
      functionDecl = nil
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

    var actions: [CodeAction] = []

    if let functionDecl,
      let removeAction = removeUnusedParameterFromLocalFunction(
        parameter: parameter,
        parameterClause: parameterClause,
        functionDecl: functionDecl,
        in: scope
      )
    {
      actions.append(removeAction)
    }

    if let replaceAction = replaceUnusedParameterWithWildcard(
      parameter: parameter,
      in: scope
    ) {
      actions.append(replaceAction)
    }

    return actions
  }

  // MARK: - Finding target parameter

  private static func findParameter(in scope: SyntaxCodeActionScope) -> FunctionParameterSyntax? {
    guard let node = scope.innermostNodeContainingRange else {
      return nil
    }
    return node.findParentOfSelf(
      ofType: FunctionParameterSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
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

  // MARK: - Remove parameter from local function action

  private static func removeUnusedParameterFromLocalFunction(
    parameter: FunctionParameterSyntax,
    parameterClause: FunctionParameterClauseSyntax,
    functionDecl: FunctionDeclSyntax,
    in scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    // Only local functions enclosed inside a code block (e.g. outer function or closure)
    // are eligible for call-site rewriting without whole-workspace indexing.
    guard let codeBlockItem = functionDecl.parent?.as(CodeBlockItemSyntax.self),
      let enclosingBlock = codeBlockItem.parent?.as(CodeBlockItemListSyntax.self),
      enclosingBlock.parent?.is(CodeBlockSyntax.self) == true
    else {
      return nil
    }

    guard let functionIdentifier = Identifier(functionDecl.name) else {
      return nil
    }

    let callFinder = LocalFunctionCallFinder(
      functionIdentifier: functionIdentifier,
      functionDeclId: functionDecl.id
    )
    callFinder.walk(Syntax(enclosingBlock))

    guard !callFinder.hasUncallableReference else {
      return nil
    }

    let parameterList = parameterClause.parameters
    var newParams = Array(parameterList)
    guard let paramIndex = newParams.firstIndex(of: parameter) else {
      return nil
    }

    let parameterName = (parameter.secondName ?? parameter.firstName).text
    var edits: [SourceEdit] = []

    // 1. Declaration edit
    newParams.remove(at: paramIndex)
    if !newParams.isEmpty {
      newParams[0].leadingTrivia = Trivia(pieces: newParams[0].leadingTrivia.drop(while: \.isWhitespace))
      newParams[newParams.count - 1].trailingComma = nil
      let replacement = FunctionParameterListSyntax(newParams).description
      edits.append(SourceEdit(range: parameterList.range, replacement: replacement))
    } else {
      let range =
        (parameterClause.leftParen
          .endPositionBeforeTrailingTrivia..<parameterClause.rightParen.positionAfterSkippingLeadingTrivia)
      edits.append(SourceEdit(range: range, replacement: ""))
    }

    // 2. Call-site edits
    let isLabeled = parameter.firstName.tokenKind != .wildcard
    let labelText = parameter.firstName.text

    for callExpr in callFinder.callSites {
      let args = callExpr.arguments
      let argToRemove: LabeledExprSyntax?

      if isLabeled {
        if let match = args.first(where: { $0.label?.text == labelText }) {
          argToRemove = match
        } else if parameter.defaultValue != nil {
          argToRemove = nil
        } else {
          return nil
        }
      } else {
        let argList = Array(args)
        guard argList.count == parameterList.count,
          argList.indices.contains(paramIndex),
          argList[paramIndex].label == nil
        else {
          return nil
        }
        argToRemove = argList[paramIndex]
      }

      guard let argToRemove else {
        continue
      }

      var newArgs = Array(args)
      guard let argIndex = newArgs.firstIndex(of: argToRemove) else {
        return nil
      }

      newArgs.remove(at: argIndex)
      if !newArgs.isEmpty {
        newArgs[0].leadingTrivia = Trivia(pieces: newArgs[0].leadingTrivia.drop(while: \.isWhitespace))
        newArgs[newArgs.count - 1].trailingComma = nil
        let replacement = LabeledExprListSyntax(newArgs).description
        edits.append(SourceEdit(range: args.range, replacement: replacement))
      } else {
        guard let leftParen = callExpr.leftParen, let rightParen = callExpr.rightParen else {
          return nil
        }
        let range = (leftParen.endPositionBeforeTrailingTrivia..<rightParen.positionAfterSkippingLeadingTrivia)
        edits.append(SourceEdit(range: range, replacement: ""))
      }
    }

    edits.sort { $0.range.lowerBound < $1.range.lowerBound }
    guard let workspaceEdit = edits.asWorkspaceEdit(snapshot: scope.snapshot) else {
      return nil
    }

    return CodeAction(
      title: "Remove unused parameter '\(parameterName)'",
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
        if names.contains(where: { $0.syntax.id == targetParameterId }) {
          isUsed = true
          return .skipChildren
        }
      default:
        continue
      }
    }
    return .visitChildren
  }
}

private final class LocalFunctionCallFinder: SyntaxVisitor {
  let functionIdentifier: Identifier
  let functionDeclId: SyntaxIdentifier
  var callSites: [FunctionCallExprSyntax] = []
  var hasUncallableReference = false

  init(functionIdentifier: Identifier, functionDeclId: SyntaxIdentifier) {
    self.functionIdentifier = functionIdentifier
    self.functionDeclId = functionDeclId
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    guard let nodeIdentifier = Identifier(node.baseName),
      nodeIdentifier == functionIdentifier
    else {
      return .visitChildren
    }

    let lookupResults = node.lookup(nodeIdentifier)
    let isThisFunction = lookupResults.contains { result in
      switch result {
      case .fromScope(_, let names):
        return names.contains { $0.syntax.id == functionDeclId }
      default:
        return false
      }
    }

    guard isThisFunction else {
      return .visitChildren
    }

    if let parentCall = node.parent?.as(FunctionCallExprSyntax.self),
      parentCall.calledExpression.id == node.id
    {
      callSites.append(parentCall)
    } else {
      hasUncallableReference = true
    }

    return .visitChildren
  }
}
