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

@_spi(Testing) public struct ConvertForEachToForIn {
  struct Candidate {
    let calleePosition: Position
    let codeAction: CodeAction
  }

  static func candidate(in scope: SyntaxCodeActionScope) -> Candidate? {
    guard let match = findForEachCall(in: scope) else {
      return nil
    }

    let callExpr = match.callExpr
    let collection = match.collection
    let closure = match.closure

    // Only offer the refactoring when the call is a standalone statement.
    // `for-in` is a statement, so it can't replace an expression in a larger context
    // like `let _ = array.forEach { ... }`.
    var current = Syntax(callExpr)
    if let parent = current.parent, parent.is(ExpressionStmtSyntax.self) {
      current = parent
    }
    guard current.parent?.is(CodeBlockItemSyntax.self) ?? false else {
      return nil
    }

    guard let itemName = extractParameterName(from: closure) else {
      return nil
    }

    let leadingTrivia = current.firstToken(viewMode: .sourceAccurate)?.leadingTrivia ?? []

    let body = ReturnToContinueRewriter().rewrite(closure.statements).cast(CodeBlockItemListSyntax.self)

    let forLoop = ForStmtSyntax(
      forKeyword: .keyword(.for, leadingTrivia: leadingTrivia, trailingTrivia: .space),
      pattern: IdentifierPatternSyntax(identifier: .identifier(itemName)),
      inKeyword: .keyword(.in, leadingTrivia: .space, trailingTrivia: .space),
      sequence: collection.trimmed,
      body: CodeBlockSyntax(
        leftBrace: .leftBraceToken(leadingTrivia: .space),
        statements: body,
        rightBrace: closure.rightBrace
      )
    )

    let edit = TextEdit(
      range: scope.snapshot.absolutePositionRange(of: current.position..<current.endPosition),
      newText: forLoop.description
    )

    let calleeToken = match.memberAccess.declName.baseName
    let calleePosition = scope.snapshot.position(
      of: calleeToken.positionAfterSkippingLeadingTrivia
    )

    return Candidate(
      calleePosition: calleePosition,
      codeAction: CodeAction(
        title: "Convert to 'for-in' loop",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    )
  }

  private struct Match {
    let callExpr: FunctionCallExprSyntax
    let memberAccess: MemberAccessExprSyntax
    let collection: ExprSyntax
    let closure: ClosureExprSyntax
  }

  private static func findForEachCall(in scope: SyntaxCodeActionScope) -> Match? {
    guard let innermostNode = scope.innermostNodeContainingRange else {
      return nil
    }

    if let callExpr = innermostNode.findParentOfSelf(
      ofType: FunctionCallExprSyntax.self,
      stoppingIf: isFunctionBoundary,
      matching: {
        guard let memberAccess = $0.calledExpression.as(MemberAccessExprSyntax.self) else {
          return false
        }
        return memberAccess.declName.baseName.text == "forEach"
      }
    ),
      let match = matchForEach(callExpr)
    {
      return match
    }

    guard let boundary = nearestFunctionBoundary(from: innermostNode),
      let closure = boundary.as(ClosureExprSyntax.self),
      let callExpr = enclosingCall(of: closure),
      let match = matchForEach(callExpr),
      Syntax(match.closure).id == Syntax(closure).id
    else {
      return nil
    }

    return match
  }

  private static func nearestFunctionBoundary(from node: Syntax) -> Syntax? {
    var current: Syntax? = node
    while let unwrappedCurrent = current {
      if isFunctionBoundary(unwrappedCurrent) {
        return unwrappedCurrent
      }
      current = unwrappedCurrent.parent
    }
    return nil
  }

  private static func enclosingCall(of closure: ClosureExprSyntax) -> FunctionCallExprSyntax? {
    var current = Syntax(closure).parent
    while let unwrappedCurrent = current {
      if let callExpr = unwrappedCurrent.as(FunctionCallExprSyntax.self) {
        return callExpr
      }
      if isFunctionBoundary(unwrappedCurrent) || unwrappedCurrent.is(CodeBlockSyntax.self)
        || unwrappedCurrent.is(MemberBlockSyntax.self)
      {
        return nil
      }
      current = unwrappedCurrent.parent
    }
    return nil
  }

  private static func matchForEach(_ callExpr: FunctionCallExprSyntax) -> Match? {
    guard let memberAccess = callExpr.calledExpression.as(MemberAccessExprSyntax.self),
      memberAccess.declName.baseName.text == "forEach",
      let collection = memberAccess.base
    else {
      return nil
    }

    let closure: ClosureExprSyntax
    if let trailingClosure = callExpr.trailingClosure {
      guard callExpr.arguments.isEmpty,
        callExpr.additionalTrailingClosures.isEmpty
      else {
        return nil
      }
      closure = trailingClosure
    } else if callExpr.arguments.count == 1,
      let closureArg = callExpr.arguments.first?.expression.as(ClosureExprSyntax.self)
    {
      closure = closureArg
    } else {
      return nil
    }

    guard hasSingleExplicitParameter(closure) else {
      return nil
    }

    return Match(
      callExpr: callExpr,
      memberAccess: memberAccess,
      collection: collection,
      closure: closure
    )
  }

  private static func hasSingleExplicitParameter(_ closure: ClosureExprSyntax) -> Bool {
    guard let signature = closure.signature,
      let parameterClause = signature.parameterClause
    else {
      return false
    }

    switch parameterClause {
    case .simpleInput(let params):
      return params.count == 1
    case .parameterClause(let clause):
      return clause.parameters.count == 1
    }
  }

  /// Returns the named parameter from the closure signature.
  private static func extractParameterName(from closure: ClosureExprSyntax) -> String? {
    guard let signature = closure.signature,
      let paramClause = signature.parameterClause
    else {
      return nil
    }

    switch paramClause {
    case .simpleInput(let params):
      guard let param = params.first else { return nil }
      return param.name.text
    case .parameterClause(let clause):
      guard let param = clause.parameters.first else { return nil }
      return (param.secondName ?? param.firstName).text
    }
  }
}

/// Rewrites bare `return` statements to `continue`, without descending into nested
/// closures or other function-like declarations.
private class ReturnToContinueRewriter: SyntaxRewriter {
  override func visit(_ node: ReturnStmtSyntax) -> StmtSyntax {
    guard node.expression == nil else {
      return StmtSyntax(node)
    }
    return StmtSyntax(
      ContinueStmtSyntax(
        continueKeyword: .keyword(
          .continue,
          leadingTrivia: node.returnKeyword.leadingTrivia,
          trailingTrivia: node.returnKeyword.trailingTrivia
        )
      )
    )
  }

  override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: AccessorDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: SubscriptDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ClosureExprSyntax) -> ExprSyntax { ExprSyntax(node) }
  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
}

private func isFunctionBoundary(_ syntax: Syntax) -> Bool {
  [.functionDecl, .initializerDecl, .accessorDecl, .subscriptDecl, .closureExpr].contains(syntax.kind)
}
