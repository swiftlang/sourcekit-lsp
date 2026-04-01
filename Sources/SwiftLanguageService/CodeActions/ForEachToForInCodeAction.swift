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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder

/// Code action to convert `.forEach { }` calls to `for-in` loops.
///
/// Uses `cursorInfo` to verify that `.forEach` refers to `Sequence.forEach` from the
/// Swift stdlib before suggesting conversion.
struct ForEachToForInCodeAction: SyntaxCodeActionProvider {
  static func codeActions(in scope: CodeActionScope) async -> [CodeAction] {
    guard let match = findForEachCall(in: scope) else {
      return []
    }

    guard let info = try? await scope.cursorInfo(), isStdlibSequenceForEach(info) else {
      return []
    }

    guard !hasReturnWithValue(match.closure) else {
      return []
    }

    guard !hasTryOrAwait(match.closure) else {
      return []
    }

    guard let paramName = extractParameterName(from: match.closure) else {
      return []
    }

    let rewrittenBody = ReturnToContinueRewriter().visit(match.closure.statements)

    let forInLoop = ForStmtSyntax(
      forKeyword: .keyword(.for, trailingTrivia: .space),
      pattern: IdentifierPatternSyntax(identifier: .identifier(paramName)),
      inKeyword: .keyword(.in, leadingTrivia: .space, trailingTrivia: .space),
      sequence: match.collection,
      body: CodeBlockSyntax(statements: rewrittenBody)
    )

    let edit = TextEdit(
      range: scope.snapshot.range(of: match.callExpr),
      newText: forInLoop.description
    )

    return [CodeAction(
      title: "Convert to 'for-in' loop",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
    )]
  }
}

// MARK: - Helpers

private struct Match {
  let callExpr: FunctionCallExprSyntax
  let memberAccess: MemberAccessExprSyntax
  let collection: ExprSyntax
  let closure: ClosureExprSyntax
}

private func findForEachCall(in scope: CodeActionScope) -> Match? {
  guard let node = scope.innermostNodeContainingRange else {
    return nil
  }

  let visitor = ForEachCallVisitor(rangeToMatch: scope.range)
  visitor.walk(node)
  return visitor.result
}

private func isStdlibSequenceForEach(_ info: CursorInfo) -> Bool {
  guard let module = info.symbolInfo.systemModule else {
    return false
  }
  return module.moduleName == "Swift"
}

private func hasReturnWithValue(_ closure: ClosureExprSyntax) -> Bool {
  let visitor = ReturnWithValueVisitor()
  visitor.walk(closure)
  return visitor.found
}

private func hasTryOrAwait(_ closure: ClosureExprSyntax) -> Bool {
  let visitor = TryAwaitVisitor()
  visitor.walk(closure)
  return visitor.found
}

private func extractParameterName(from closure: ClosureExprSyntax) -> String? {
  guard let signature = closure.signature else {
    return nil
  }

  guard let parameters = signature.parameterClause?.as(ClosureParameterClauseSyntax.self) else {
    return nil
  }

  guard parameters.parameters.count == 1 else {
    return nil
  }

  guard let param = parameters.parameters.first else {
    return nil
  }

  // Reject if parameter is shorthand $0 syntax
  if param.firstName.text == "$0" {
    return nil
  }

  return param.firstName.text
}

// MARK: - Syntax Visitors

private class ForEachCallVisitor: SyntaxVisitor {
  var result: Match? = nil
  let rangeToMatch: Range<AbsolutePosition>

  init(rangeToMatch: Range<AbsolutePosition>) {
    self.rangeToMatch = rangeToMatch
    super.init(viewMode: .all)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard node.position >= rangeToMatch.lowerBound && node.endPosition <= rangeToMatch.upperBound else {
      return .visitChildren
    }

    guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
          memberAccess.declName.baseName.text == "forEach",
          let collection = memberAccess.base else {
      return .visitChildren
    }

    let closure: ClosureExprSyntax?
    if let trailingClosure = node.trailingClosure {
      closure = trailingClosure
    } else if node.arguments.count == 1,
              let closureArg = node.arguments.first?.expression.as(ClosureExprSyntax.self) {
      closure = closureArg
    } else {
      return .visitChildren
    }

    guard let closure = closure else {
      return .visitChildren
    }

    self.result = Match(
      callExpr: node,
      memberAccess: memberAccess,
      collection: collection,
      closure: closure
    )
    return .skipChildren
  }
}

private class ReturnWithValueVisitor: SyntaxVisitor {
  var found = false

  required override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
    if node.expression != nil {
      found = true
      return .skipChildren
    }
    return .visitChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    return .skipChildren
  }

  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
    return .skipChildren
  }
}

private class TryAwaitVisitor: SyntaxVisitor {
  var found = false

  required override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
    found = true
    return .skipChildren
  }

  override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
    found = true
    return .skipChildren
  }
}

// MARK: - Syntax Rewriting

/// Rewrites bare `return` statements to `continue` within the closure body,
/// skipping `return <expr>` (which would change semantics).
private class ReturnToContinueRewriter: SyntaxRewriter {
  override func visit(_ node: ReturnStmtSyntax) -> StmtSyntax {
    guard node.expression == nil else {
      return StmtSyntax(node)
    }
    return StmtSyntax(ContinueStmtSyntax())
  }

  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
    DeclSyntax(node)
  }

  override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
    ExprSyntax(node)
  }
}
