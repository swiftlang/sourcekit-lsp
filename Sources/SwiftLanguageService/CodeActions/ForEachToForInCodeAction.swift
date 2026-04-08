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
import SwiftBasicFormat
import SwiftSyntax
import SwiftSyntaxBuilder

/// Code action to convert `.forEach { }` calls to `for-in` loops.
///
/// Only active when the cursor is on the `forEach` token. Uses shared `cursorInfo`
/// to verify that `.forEach` refers to `Sequence.forEach` from the Swift stdlib.
struct ForEachToForInCodeAction: SyntaxCodeActionProvider {
  static func codeActions(in scope: CodeActionScope) async -> [CodeAction] {
    guard let match = findForEachCall(in: scope) else {
      return []
    }

    guard let info = try? await scope.cursorInfo(),
          isStdlibSequenceForEach(info) else {
      return []
    }

    let eligibility = checkClosureEligibility(match.closure)
    guard eligibility.isEligible else {
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
    let indentationWidth = BasicFormat.inferIndentation(of: Syntax(scope.file)) ?? .spaces(2)
    let baseIndentation = match.callExpr.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []

    var forInLoop = ForStmtSyntax(
      forKeyword: .keyword(.for, trailingTrivia: .space),
      pattern: IdentifierPatternSyntax(identifier: .identifier(param.name)),
      typeAnnotation: param.typeAnnotation,
      inKeyword: .keyword(.in, leadingTrivia: .space, trailingTrivia: .space),
      sequence: match.sequence.trimmed,
      body: CodeBlockSyntax(
        leftBrace: .leftBraceToken(leadingTrivia: .space),
        statements: rewrittenBody,
        rightBrace: .rightBraceToken()
      )
    )
    let format = BasicFormat(indentationWidth: indentationWidth, initialIndentation: baseIndentation)
    forInLoop = forInLoop.formatted(using: format).cast(ForStmtSyntax.self)
    forInLoop.leadingTrivia = []

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
  let sequence: ExprSyntax
  let closure: ClosureExprSyntax
}

/// Matches only when the cursor/selection is on the `forEach` token.
private func findForEachCall(in scope: CodeActionScope) -> Match? {
  guard let token = selectedForEachToken(in: scope),
        token.text == "forEach",
        let memberName = token.parent?.as(DeclReferenceExprSyntax.self),
        let memberAccess = memberName.parent?.as(MemberAccessExprSyntax.self),
        memberAccess.declName.id == memberName.id,
        let callExpr = memberAccess.parent?.as(FunctionCallExprSyntax.self),
        callExpr.calledExpression.id == memberAccess.id,
        let sequence = memberAccess.base
  else {
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
    sequence: sequence,
    closure: closure
  )
}

private func selectedForEachToken(in scope: CodeActionScope) -> TokenSyntax? {
  let lowerBound = scope.snapshot.absolutePosition(of: scope.request.range.lowerBound)
  let upperBound = scope.snapshot.absolutePosition(of: scope.request.range.upperBound)

  guard let token = tokenAtRequestStart(in: scope.file, at: lowerBound),
        lowerBound == token.position
  else {
    return nil
  }

  guard upperBound == lowerBound || upperBound == token.endPositionBeforeTrailingTrivia else {
    return nil
  }

  return token
}

private func tokenAtRequestStart(in file: SourceFileSyntax, at position: AbsolutePosition) -> TokenSyntax? {
  if position == file.endPosition {
    return file.endOfFileToken.previousToken(viewMode: .sourceAccurate)
  }
  return file.token(at: position)
}

private func isStdlibSequenceForEach(_ info: CursorInfo) -> Bool {
  guard let module = info.symbolInfo.systemModule else {
    return false
  }
  return module.moduleName == "Swift"
}

// MARK: - Closure Eligibility

private struct ClosureEligibility {
  var hasReturnWithValue = false
  var hasAwait = false

  var isEligible: Bool { !hasReturnWithValue && !hasAwait }
}

/// Checks whether the closure body is eligible for conversion in a single pass.
private func checkClosureEligibility(_ closure: ClosureExprSyntax) -> ClosureEligibility {
  let visitor = ClosureEligibilityVisitor()
  visitor.walk(closure.statements)
  return visitor.result
}

private class ClosureEligibilityVisitor: SyntaxVisitor {
  var result = ClosureEligibility()

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
    if node.expression != nil {
      result.hasReturnWithValue = true
    }
    return result.isEligible ? .visitChildren : .skipChildren
  }

  override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
    result.hasAwait = true
    return result.isEligible ? .visitChildren : .skipChildren
  }

  // Don't dig into nested scopes.
  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

// MARK: - Parameter Extraction

private struct ClosureParam {
  let name: String
  let typeAnnotation: TypeAnnotationSyntax?
  /// Whether the body needs `$0` references rewritten to `name`.
  let needsDollarZeroRewrite: Bool
}

private func extractParameter(from closure: ClosureExprSyntax) -> ClosureParam? {
  guard let signature = closure.signature else {
    // No signature → anonymous $0 usage.
    let name = generateUniqueName(in: closure.statements)
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

/// Generates a unique name starting with "element" that doesn't conflict with existing identifiers.
private func generateUniqueName(in node: some SyntaxProtocol) -> String {
  if !containsIdentifier(named: "element", in: node) {
    return "element"
  }
  var counter = 1
  while containsIdentifier(named: "element\(counter)", in: node) {
    counter += 1
  }
  return "element\(counter)"
}

/// Checks if the node contains an identifier with the given name.
private func containsIdentifier(named name: String, in node: some SyntaxProtocol) -> Bool {
  for token in node.tokens(viewMode: .sourceAccurate) {
    if case .identifier(let tokenName) = token.tokenKind, tokenName == name {
      return true
    }
  }
  return false
}

// MARK: - Syntax Rewriting

/// Rewrites bare `return` statements to `continue` within the closure body,
/// skipping nested scopes where `return` has different semantics.
private class ReturnToContinueRewriter: SyntaxRewriter {
  override func visit(_ node: ReturnStmtSyntax) -> StmtSyntax {
    guard node.expression == nil else {
      return StmtSyntax(node)
    }
    return StmtSyntax(ContinueStmtSyntax())
  }

  // Don't dig into nested scopes.
  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: DeinitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ClosureExprSyntax) -> ExprSyntax { ExprSyntax(node) }
  override func visit(_ node: AccessorBlockSyntax) -> AccessorBlockSyntax { node }
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

  // Don't dig into nested scopes.
  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: DeinitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ClosureExprSyntax) -> ExprSyntax { ExprSyntax(node) }
  override func visit(_ node: AccessorBlockSyntax) -> AccessorBlockSyntax { node }
}
