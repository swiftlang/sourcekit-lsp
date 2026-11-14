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
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Code action to convert `.forEach { }` calls to `for-in` loops.
///
/// Offered inside the `forEach` call without crossing nested declaration scopes. Resolving the action
/// verifies that the symbol is the standard library's `Sequence.forEach` before generating edits.
struct ForEachToForInCodeAction: ResolvableSyntaxRefactoringCodeActionProvider {
  typealias Input = FunctionCallExprSyntax

  static let title = "Convert to 'for-in' loop"

  typealias Context = Void

  struct UnresolvedData: Codable, LSPAnyCodable {
    let position: Position
  }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    guard scope.resolveSupport?.canResolveEdit ?? false,
      let call = scope.innermostNodeContainingRange?.findParentOfSelf(
        ofType: FunctionCallExprSyntax.self,
        stoppingIf: { isNestedDeclaration($0) || $0.is(AccessorBlockSyntax.self) },
        matching: {
          $0.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "forEach"
        }
      ),
      let match = Match(call),
      checkClosureEligibility(match.closure).isEligible,
      extractParameter(from: match.closure) != nil
    else {
      return nil
    }
    return call
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
    // Concrete receivers can have a synthesized USR for the same Sequence extension method.
    let forEachUSR = "s:STsE7forEachyyy7ElementQzKXEKF"
    guard let info = try await symbolInfo(data.position).only,
      info.systemModule?.moduleName == "Swift",
      let usr = info.usr,
      usr == forEachUSR || usr.hasPrefix(forEachUSR + "::SYNTHESIZED::")
    else {
      throw RefactoringNotApplicableError("Only the Swift standard library's forEach can be converted to a for-in loop")
    }
    return ()
  }

  static func textRefactor(syntax: Input, in context: Context) throws -> [SourceEdit] {
    guard let match = Match(syntax), let param = extractParameter(from: match.closure) else {
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
      ? generateUniqueName(startingWith: "LOOP", in: match.closure.statements) : nil
    let rewrittenBody = ReturnToContinueRewriter(loopLabel: loopLabel).visit(body)
    var sequence = match.sequence.trimmed
    if let tryExpr = match.expression.as(TryExprSyntax.self) {
      // Evaluating the sequence can throw as well as invoking the closure.
      sequence = ExprSyntax(tryExpr.with(\.expression, sequence).with(\.leadingTrivia, []))
    }
    // The body stays at the same nesting depth; preserve its trivia instead of reformatting it.
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
    return [SourceEdit(range: match.expression.trimmedRange, replacement: replacement.description)]
  }
}

// MARK: - Helpers

/// The parts of a standalone `forEach` call needed to construct a loop.
private struct Match {
  /// The expression replaced by the loop, including an outer `try` if present.
  let expression: ExprSyntax
  /// The receiver whose elements the loop iterates over.
  let sequence: ExprSyntax
  /// The closure whose parameter and statements become the loop pattern and body.
  let closure: ClosureExprSyntax

  init?(_ callExpr: FunctionCallExprSyntax) {
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
      // Optional and forced tries change error handling for the entire loop.
      guard tryExpr.questionOrExclamationMark == nil else { return nil }
      expression = ExprSyntax(tryExpr)
    }
    // A loop must occupy a statement position, not an initializer, argument, or return expression.
    guard expression.parent?.is(CodeBlockItemSyntax.self) == true else {
      return nil
    }

    let closure: ClosureExprSyntax
    if let trailingClosure = callExpr.trailingClosure, callExpr.arguments.isEmpty {
      closure = trailingClosure
    } else if callExpr.trailingClosure == nil,
      let argument = callExpr.arguments.only, argument.label == nil,
      let closureArg = argument.expression.as(ClosureExprSyntax.self)
    {
      closure = closureArg
    } else {
      return nil
    }

    self.expression = expression
    self.sequence = sequence
    self.closure = closure
  }
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

// MARK: - Closure Eligibility

private struct ClosureEligibility {
  /// A plain continue would target the nested loop, so these returns need a loop label.
  var hasBareReturnInNestedLoop = false
  /// Returning a value needs its expression evaluated, which a continue cannot preserve.
  var hasReturnWithValue = false
  /// Sequence.forEach has a synchronous body; an async closure is not supported.
  var hasAwait = false

  var isEligible: Bool { !hasReturnWithValue && !hasAwait }
}

/// Checks whether the closure body is eligible for conversion in a single pass.
private func checkClosureEligibility(_ closure: ClosureExprSyntax) -> ClosureEligibility {
  let visitor = ClosureEligibilityVisitor()
  visitor.walk(closure.statements)
  return visitor.result
}

/// Initializers, conditional compilation blocks, and macro arguments are part of the enclosing scope.
private func isNestedDeclaration(_ node: Syntax) -> Bool {
  node.is(DeclSyntax.self) && !node.is(VariableDeclSyntax.self) && !node.is(IfConfigDeclSyntax.self)
    && !node.is(MacroExpansionDeclSyntax.self)
}

private class ClosureEligibilityVisitor: SyntaxAnyVisitor {
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

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if isNestedDeclaration(node) || node.is(ClosureExprSyntax.self) || node.is(AccessorBlockSyntax.self) {
      return .skipChildren
    }
    return result.isEligible ? .visitChildren : .skipChildren
  }
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

  // Capture initializers and ownership cannot be transferred to a loop without changing their lifetime.
  guard signature.capture == nil else { return nil }
  // Closure attributes, such as actor isolation, have no equivalent on a for-in body.
  guard signature.attributes.isEmpty else { return nil }
  // A for-in loop cannot preserve an explicitly asynchronous closure's execution context.
  guard signature.effectSpecifiers?.asyncSpecifier == nil else { return nil }

  guard let paramClause = signature.parameterClause else {
    return nil
  }

  switch paramClause {
  case .simpleInput(let params):
    // `{ item in ... }`
    guard let p = params.only else { return nil }
    return ClosureParam(name: p.name.text, typeAnnotation: nil, needsDollarZeroRewrite: false)
  case .parameterClause(let clause):
    // `{ (item) in ... }` or `{ (item: Type) in ... }`
    // Parameter attributes, ownership modifiers, and variadics are not valid loop bindings.
    guard let p = clause.parameters.only,
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

  override func visitAny(_ node: Syntax) -> Syntax? {
    // Returns in nested declarations and closures belong to that scope, not the forEach body.
    if isNestedDeclaration(node) || node.is(ClosureExprSyntax.self) || node.is(AccessorBlockSyntax.self) {
      return node
    }
    return nil
  }
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

  override func visitAny(_ node: Syntax) -> Syntax? {
    if isNestedDeclaration(node) || node.is(AccessorBlockSyntax.self) {
      return node
    }
    return nil
  }
}
