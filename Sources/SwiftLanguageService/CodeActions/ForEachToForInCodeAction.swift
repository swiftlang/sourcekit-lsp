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

    let forEachPosition = match.memberAccess.declName.baseName.positionAfterSkippingLeadingTrivia
    guard let info = try? await scope.cursorInfo(at: forEachPosition),
          isStdlibSequenceForEach(info) else {
      return []
    }

    guard !hasReturnWithValue(match.closure) else {
      return []
    }

    guard !hasAwait(match.closure) else {
      return []
    }

    guard let param = extractParameter(from: match.closure) else {
      return []
    }

    var body = match.closure.statements
    if param.needsDollarZeroRewrite {
      body = DollarZeroRewriter(replacement: param.name).visit(body)
    }
    let rewrittenBody = ReturnToContinueRewriter().visit(body)

    let forInLoop = ForStmtSyntax(
      forKeyword: .keyword(.for, trailingTrivia: .space),
      pattern: IdentifierPatternSyntax(identifier: .identifier(param.name)),
      typeAnnotation: param.typeAnnotation,
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

  // Walk up from the innermost node to find a forEach call expression,
  // stopping at function/closure boundaries to avoid matching distant calls.
  guard let callExpr = node.findParentOfSelf(
    ofType: FunctionCallExprSyntax.self,
    stoppingIf: { $0.is(FunctionDeclSyntax.self) || $0.is(ClosureExprSyntax.self) },
    matching: { call in
      guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "forEach" else {
        return false
      }
      return true
    }
  ) else {
    return nil
  }

  guard let memberAccess = callExpr.calledExpression.as(MemberAccessExprSyntax.self),
        let collection = memberAccess.base else {
    return nil
  }

  let closure: ClosureExprSyntax?
  if let trailingClosure = callExpr.trailingClosure {
    closure = trailingClosure
  } else if callExpr.arguments.count == 1,
            let closureArg = callExpr.arguments.first?.expression.as(ClosureExprSyntax.self) {
    closure = closureArg
  } else {
    return nil
  }

  guard let closure else {
    return nil
  }

  return Match(
    callExpr: callExpr,
    memberAccess: memberAccess,
    collection: collection,
    closure: closure
  )
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

private func hasAwait(_ closure: ClosureExprSyntax) -> Bool {
  let visitor = AwaitVisitor()
  visitor.walk(closure)
  return visitor.found
}

private struct ClosureParam {
  let name: String
  let typeAnnotation: TypeAnnotationSyntax?
  /// Whether the body needs `$0` references rewritten to `name`.
  let needsDollarZeroRewrite: Bool
}

private func extractParameter(from closure: ClosureExprSyntax) -> ClosureParam? {
  guard let signature = closure.signature else {
    // No signature → anonymous $0 usage.
    let name = generateUniqueName(avoiding: collectIdentifiers(in: closure.statements))
    return ClosureParam(name: name, typeAnnotation: nil, needsDollarZeroRewrite: true)
  }

  guard let paramClause = signature.parameterClause else {
    return nil
  }

  switch paramClause {
  case .simpleInput(let params):
    // `{ item in ... }`
    guard params.count == 1, let p = params.first else { return nil }
    return ClosureParam(name: p.name.text, typeAnnotation: nil, needsDollarZeroRewrite: false)
  case .parameterClause(let clause):
    // `{ (item) in ... }` or `{ (item: Type) in ... }`
    guard clause.parameters.count == 1, let p = clause.parameters.first else { return nil }
    let typeAnnotation = p.type.map {
      TypeAnnotationSyntax(colon: .colonToken(trailingTrivia: .space), type: $0)
    }
    return ClosureParam(name: p.firstName.text, typeAnnotation: typeAnnotation, needsDollarZeroRewrite: false)
  }
}

/// Collects all identifier names used in the given syntax node.
private func collectIdentifiers(in node: some SyntaxProtocol) -> Set<String> {
  var names = Set<String>()
  for token in node.tokens(viewMode: .sourceAccurate) {
    if case .identifier(let name) = token.tokenKind {
      names.insert(name)
    }
  }
  return names
}

/// Generates a unique name that doesn't conflict with existing identifiers.
private func generateUniqueName(avoiding existingNames: Set<String>) -> String {
  if !existingNames.contains("element") {
    return "element"
  }
  var counter = 1
  while existingNames.contains("element\(counter)") {
    counter += 1
  }
  return "element\(counter)"
}

// MARK: - Syntax Visitors

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

  override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
    return .skipChildren
  }
}

private class AwaitVisitor: SyntaxVisitor {
  var found = false

  required override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
    found = true
    return .skipChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    return .skipChildren
  }

  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
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

  override func visit(_ node: AccessorDeclSyntax) -> DeclSyntax {
    DeclSyntax(node)
  }
}

/// Rewrites `$0` references to a named identifier.
private class DollarZeroRewriter: SyntaxRewriter {
  let replacement: String

  init(replacement: String) {
    self.replacement = replacement
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
    guard node.baseName.text == "$0" else {
      return ExprSyntax(node)
    }
    return ExprSyntax(
      node.with(\.baseName, .identifier(replacement, leadingTrivia: node.baseName.leadingTrivia, trailingTrivia: node.baseName.trailingTrivia))
    )
  }

  override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
    ExprSyntax(node)
  }
}
