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
import SwiftBasicFormat
import SwiftRefactor
import SwiftSyntax
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Code action to convert `.forEach { }` calls to `for-in` loops.
///
/// Offered on the `forEach` token. Resolving the action verifies that the symbol
/// is from the Swift standard library before generating edits.
struct ForEachToForInCodeAction: ResolvableSyntaxRefactoringCodeActionProvider {
  typealias Input = FunctionCallExprSyntax

  static let title = "Convert to 'for-in' loop"

  struct Context {
    let indentationWidth: Trivia
  }

  struct UnresolvedData: Codable, LSPAnyCodable {
    let position: Position
  }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    guard scope.resolveSupport?.canResolveEdit ?? false,
      let match = findForEachCall(in: scope),
      checkClosureEligibility(match.closure).isEligible,
      extractParameter(from: match.closure) != nil
    else {
      return nil
    }
    return match.callExpr
  }

  static func refactoringContext(
    for node: Input,
    in scope: SyntaxCodeActionScope
  ) -> RefactoringContext<Context, UnresolvedData> {
    let member = node.calledExpression.cast(MemberAccessExprSyntax.self)
    return .unresolved(
      UnresolvedData(position: scope.snapshot.position(of: member.declName.baseName.positionAfterSkippingLeadingTrivia))
    )
  }

  static func resolveContext(
    for data: UnresolvedData,
    in scope: SyntaxCodeActionScope,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> Context {
    guard let info = try await symbolInfo(data.position).only,
      info.systemModule?.moduleName == "Swift"
    else {
      throw RefactoringNotApplicableError("Only the Swift standard library's forEach can be converted to a for-in loop")
    }
    return Context(indentationWidth: BasicFormat.inferIndentation(of: Syntax(scope.file)) ?? .spaces(2))
  }

  static func textRefactor(syntax: Input, in context: Context) throws -> [SourceEdit] {
    guard let match = matchForEachCall(syntax), let param = extractParameter(from: match.closure) else {
      throw RefactoringNotApplicableError("Unsupported forEach closure")
    }

    let eligibility = checkClosureEligibility(match.closure)
    guard eligibility.isEligible else {
      throw RefactoringNotApplicableError("Unsupported control flow in forEach closure")
    }

    var body = match.closure.statements
    if param.needsDollarZeroRewrite {
      body = DollarZeroRewriter(replacement: param.name).visit(body)
    }
    let loopLabel =
      eligibility.hasBareReturnInNestedLoop
      ? generateUniqueName(startingWith: "forEachLoop", in: match.closure.statements) : nil
    let rewrittenBody = ReturnToContinueRewriter(loopLabel: loopLabel).visit(body)
    let baseIndentation = match.expression.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    var sequence = match.sequence.trimmed
    if let tryExpr = match.expression.as(TryExprSyntax.self) {
      // Evaluating the sequence can throw as well as invoking the closure.
      sequence = ExprSyntax(tryExpr.with(\.expression, sequence).with(\.leadingTrivia, []))
    }
    let bodyTrivia = match.closure.signature?.inKeyword.trailingTrivia ?? match.closure.leftBrace.trailingTrivia

    let forInLoop = ForStmtSyntax(
      forKeyword: .keyword(.for, trailingTrivia: .space),
      pattern: IdentifierPatternSyntax(identifier: .identifier(param.name)),
      typeAnnotation: param.typeAnnotation,
      inKeyword: .keyword(.in, leadingTrivia: .space, trailingTrivia: .space),
      sequence: sequence,
      body: CodeBlockSyntax(
        leftBrace: .leftBraceToken(leadingTrivia: .space, trailingTrivia: bodyTrivia),
        statements: rewrittenBody,
        rightBrace: match.closure.rightBrace.with(\.trailingTrivia, [])
      )
    )
    var replacement = StmtSyntax(forInLoop)
    if let loopLabel {
      replacement = StmtSyntax(
        LabeledStmtSyntax(
          label: .identifier(loopLabel),
          colon: .colonToken(trailingTrivia: .space),
          statement: forInLoop
        )
      )
    }
    let format = BasicFormat(indentationWidth: context.indentationWidth, initialIndentation: baseIndentation)
    replacement.leadingTrivia = baseIndentation
    replacement = replacement.formatted(using: format).cast(StmtSyntax.self)
    replacement.leadingTrivia = []

    return [SourceEdit(range: match.expression.trimmedRange, replacement: replacement.description)]
  }
}

// MARK: - Helpers

private struct Match {
  let callExpr: FunctionCallExprSyntax
  let expression: ExprSyntax
  let sequence: ExprSyntax
  let closure: ClosureExprSyntax
}

/// Matches only when the cursor/selection is on the `forEach` token.
private func findForEachCall(in scope: SyntaxCodeActionScope) -> Match? {
  guard let token = selectedForEachToken(in: scope),
    token.text == "forEach",
    let memberName = token.parent?.as(DeclReferenceExprSyntax.self),
    let memberAccess = memberName.parent?.as(MemberAccessExprSyntax.self),
    memberAccess.declName.id == memberName.id,
    let callExpr = memberAccess.parent?.as(FunctionCallExprSyntax.self),
    callExpr.calledExpression.id == memberAccess.id
  else {
    return nil
  }
  return matchForEachCall(callExpr)
}

private func matchForEachCall(_ callExpr: FunctionCallExprSyntax) -> Match? {
  guard let memberAccess = callExpr.calledExpression.as(MemberAccessExprSyntax.self),
    memberAccess.declName.baseName.text == "forEach",
    let sequence = memberAccess.base,
    !hasOptionalChaining(sequence),
    callExpr.additionalTrailingClosures.isEmpty
  else {
    return nil
  }

  var expression = ExprSyntax(callExpr)
  if let tryExpr = callExpr.parent?.as(TryExprSyntax.self) {
    guard tryExpr.questionOrExclamationMark == nil else { return nil }
    expression = ExprSyntax(tryExpr)
  }
  // A loop can only replace a standalone expression, not a value used by another expression.
  guard isStatementContext(Syntax(expression)) else {
    return nil
  }

  let closure: ClosureExprSyntax
  if let trailingClosure = callExpr.trailingClosure, callExpr.arguments.isEmpty {
    closure = trailingClosure
  } else if callExpr.trailingClosure == nil, callExpr.arguments.count == 1,
    let argument = callExpr.arguments.first, argument.label == nil,
    let closureArg = argument.expression.as(ClosureExprSyntax.self)
  {
    closure = closureArg
  } else {
    return nil
  }

  let bodyStart = closure.signature?.inKeyword ?? closure.leftBrace
  var preservedRanges = [
    sequence.trimmedRange,
    bodyStart.endPositionBeforeTrailingTrivia..<bodyStart.endPosition,
    closure.statements.position..<closure.statements.endPosition,
    closure.rightBrace.position..<closure.rightBrace.endPositionBeforeTrailingTrivia,
  ]
  if let tryExpr = expression.as(TryExprSyntax.self) {
    preservedRanges.append(tryExpr.tryKeyword.trimmedRange.lowerBound..<tryExpr.tryKeyword.endPosition)
  }
  guard !hasDiscardedComment(in: expression, preserving: preservedRanges) else {
    return nil
  }

  return Match(
    callExpr: callExpr,
    expression: expression,
    sequence: sequence,
    closure: closure
  )
}

/// A sole expression can implicitly return a value from a function, closure, getter, or branch.
private func isStatementContext(_ node: Syntax) -> Bool {
  if let parent = node.parent, parent.is(ExpressionStmtSyntax.self) || parent.is(IfExprSyntax.self) {
    return isStatementContext(parent)
  }
  guard let item = node.parent?.as(CodeBlockItemSyntax.self),
    let statements = item.parent?.as(CodeBlockItemListSyntax.self)
  else { return false }
  guard statements.count == 1 else { return true }
  if let closure = statements.parent?.as(ClosureExprSyntax.self) {
    return closure.signature?.returnClause?.type.isVoid ?? false
  }
  if statements.parent?.is(AccessorBlockSyntax.self) == true {
    return false
  }
  if let switchCase = statements.parent?.as(SwitchCaseSyntax.self),
    let switchExpr = switchCase.parent?.parent?.as(SwitchExprSyntax.self)
  {
    return isStatementContext(Syntax(switchExpr))
  }
  if let owner = statements.parent?.as(CodeBlockSyntax.self)?.parent {
    if let function = owner.as(FunctionDeclSyntax.self) {
      return function.signature.returnClause?.type.isVoid ?? true
    }
    if let accessor = owner.as(AccessorDeclSyntax.self) {
      return accessor.accessorSpecifier.tokenKind != .keyword(.get)
    }
    if owner.is(IfExprSyntax.self) {
      return isStatementContext(owner)
    }
  }
  return true
}

/// Optional chaining propagates through the receiver's postfix expression, but not its arguments.
private func hasOptionalChaining(_ expression: ExprSyntax) -> Bool {
  if expression.is(OptionalChainingExprSyntax.self) {
    return true
  } else if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {
    return hasOptionalChaining(base)
  } else if let call = expression.as(FunctionCallExprSyntax.self) {
    return hasOptionalChaining(call.calledExpression)
  } else if let subscriptCall = expression.as(SubscriptCallExprSyntax.self) {
    return hasOptionalChaining(subscriptCall.calledExpression)
  } else if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
    return hasOptionalChaining(specialization.expression)
  } else if let unwrap = expression.as(ForceUnwrapExprSyntax.self) {
    return hasOptionalChaining(unwrap.expression)
  }
  return false
}

/// Decline the action if removing the call or closure signature would discard a comment.
private func hasDiscardedComment(in expression: ExprSyntax, preserving ranges: [Range<AbsolutePosition>]) -> Bool {
  for token in expression.tokens(viewMode: .sourceAccurate) {
    for (trivia, start) in [
      (token.leadingTrivia, token.position),
      (token.trailingTrivia, token.endPositionBeforeTrailingTrivia),
    ] {
      var position = start
      for piece in trivia {
        let end = position + piece.sourceLength
        defer { position = end }
        if piece.isComment, expression.trimmedRange.contains(position),
          !ranges.contains(where: { $0.lowerBound <= position && end <= $0.upperBound })
        {
          return true
        }
      }
    }
  }
  return false
}

/// Matches the original request range against a single token exactly. We cannot rely on
/// `scope.innermostNodeContainingRange` for this because `SyntaxCodeActionScope` normalizes the
/// selection via `tokenForRefactoring`, which may shift a boundary-position cursor to the
/// previous token.
private func selectedForEachToken(in scope: SyntaxCodeActionScope) -> TokenSyntax? {
  let lowerBound = scope.snapshot.absolutePosition(of: scope.requestedRange.lowerBound)
  let upperBound = scope.snapshot.absolutePosition(of: scope.requestedRange.upperBound)

  guard let token = scope.file.token(at: lowerBound),
    lowerBound == token.position
  else {
    return nil
  }

  guard upperBound == lowerBound || upperBound == token.endPositionBeforeTrailingTrivia else {
    return nil
  }

  return token
}

// MARK: - Closure Eligibility

private struct ClosureEligibility {
  var hasBareReturnInNestedLoop = false
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
  private var nestedLoopCount = 0

  var result = ClosureEligibility()

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
    if node.expression != nil {
      result.hasReturnWithValue = true
    } else if nestedLoopCount > 0 {
      result.hasBareReturnInNestedLoop = true
    }
    return result.isEligible ? .visitChildren : .skipChildren
  }

  override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
    result.hasAwait = true
    return result.isEligible ? .visitChildren : .skipChildren
  }

  override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
    nestedLoopCount += 1
    return .visitChildren
  }

  override func visitPost(_ node: ForStmtSyntax) {
    nestedLoopCount -= 1
  }

  override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
    nestedLoopCount += 1
    return .visitChildren
  }

  override func visitPost(_ node: WhileStmtSyntax) {
    nestedLoopCount -= 1
  }

  override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
    nestedLoopCount += 1
    return .visitChildren
  }

  override func visitPost(_ node: RepeatStmtSyntax) {
    nestedLoopCount -= 1
  }

  // Don't dig into nested scopes.
  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
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
    let name = generateUniqueName(startingWith: "element", in: closure.statements)
    return ClosureParam(name: name, typeAnnotation: nil, needsDollarZeroRewrite: true)
  }

  guard signature.capture == nil, signature.attributes.isEmpty,
    signature.effectSpecifiers?.asyncSpecifier == nil
  else {
    return nil
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
    guard clause.parameters.count == 1, let p = clause.parameters.first,
      p.attributes.isEmpty, p.modifiers.isEmpty, p.ellipsis == nil
    else { return nil }
    let typeAnnotation = p.type.map {
      TypeAnnotationSyntax(colon: .colonToken(trailingTrivia: .space), type: $0)
    }
    return ClosureParam(
      name: (p.secondName ?? p.firstName).text,
      typeAnnotation: typeAnnotation,
      needsDollarZeroRewrite: false
    )
  @unknown default:
    return nil
  }
}

/// Generates a name that doesn't conflict with existing identifiers, including escaped identifiers.
private func generateUniqueName(startingWith baseName: String, in node: some SyntaxProtocol) -> String {
  var name = baseName
  var suffix = 0
  while node.tokens(viewMode: .sourceAccurate).contains(where: { $0.identifier?.name == name }) {
    suffix += 1
    name = "\(baseName)\(suffix)"
  }
  return name
}

// MARK: - Syntax Rewriting

/// Rewrites bare `return` statements to `continue` within the closure body,
/// skipping nested scopes where `return` has different semantics.
private class ReturnToContinueRewriter: SyntaxRewriter {
  private var nestedLoopCount = 0
  private let loopLabel: String?

  init(loopLabel: String?) {
    self.loopLabel = loopLabel
  }

  override func visit(_ node: ReturnStmtSyntax) -> StmtSyntax {
    guard node.expression == nil else {
      return StmtSyntax(node)
    }
    let label = nestedLoopCount > 0 ? loopLabel : nil
    return StmtSyntax(
      ContinueStmtSyntax(
        continueKeyword: .keyword(
          .continue,
          leadingTrivia: node.returnKeyword.leadingTrivia,
          trailingTrivia: label == nil ? node.returnKeyword.trailingTrivia : .space
        ),
        label: label.map { .identifier($0, trailingTrivia: node.returnKeyword.trailingTrivia) }
      )
    )
  }

  override func visit(_ node: ForStmtSyntax) -> StmtSyntax {
    nestedLoopCount += 1
    defer { nestedLoopCount -= 1 }
    return super.visit(node)
  }

  override func visit(_ node: WhileStmtSyntax) -> StmtSyntax {
    nestedLoopCount += 1
    defer { nestedLoopCount -= 1 }
    return super.visit(node)
  }

  override func visit(_ node: RepeatStmtSyntax) -> StmtSyntax {
    nestedLoopCount += 1
    defer { nestedLoopCount -= 1 }
    return super.visit(node)
  }

  // Don't dig into nested scopes.
  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: DeinitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ActorDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ClassDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ClosureExprSyntax) -> ExprSyntax { ExprSyntax(node) }
  override func visit(_ node: EnumDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ExtensionDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ProtocolDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: AccessorBlockSyntax) -> AccessorBlockSyntax { node }
  override func visit(_ node: StructDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
}

/// Rewrites `$0` references to a named identifier.
private class DollarZeroRewriter: SyntaxRewriter {
  let replacement: String

  init(replacement: String) {
    self.replacement = replacement
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
    guard node.baseName.identifier?.name == "$0" else {
      return ExprSyntax(node)
    }
    return ExprSyntax(
      node.with(
        \.baseName,
        .identifier(
          replacement,
          leadingTrivia: node.baseName.leadingTrivia,
          trailingTrivia: node.baseName.trailingTrivia
        )
      )
    )
  }

  override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
    // Capture initializers belong to the enclosing scope; the nested body has its own parameters.
    guard var signature = node.signature, var capture = signature.capture else {
      return ExprSyntax(node)
    }
    capture.items = ClosureCaptureListSyntax(
      capture.items.map { item in
        guard let initializer = item.initializer else { return item }
        return item.with(\.initializer, initializer.with(\.value, visit(initializer.value)))
      }
    )
    signature.capture = capture
    return ExprSyntax(node.with(\.signature, signature))
  }

  // Don't dig into nested scopes.
  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: DeinitializerDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ActorDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ClassDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: EnumDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ExtensionDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: ProtocolDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
  override func visit(_ node: AccessorBlockSyntax) -> AccessorBlockSyntax { node }
  override func visit(_ node: StructDeclSyntax) -> DeclSyntax { DeclSyntax(node) }
}
