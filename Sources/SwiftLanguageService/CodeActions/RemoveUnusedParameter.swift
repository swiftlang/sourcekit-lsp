//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
import Csourcekitd
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

/// Remove a function parameter that is not used in the function body and update
/// all call sites (in the same file) to drop the corresponding argument.
///
/// Before:
/// ```swift
/// func greet(name: String, title: String) {
///   print("Hello, \(name)")
/// }
/// greet(name: "Alice", title: "Ms.")
/// ```
///
/// After:
/// ```swift
/// func greet(name: String) {
///   print("Hello, \(name)")
/// }
/// greet(name: "Alice")
/// ```
extension SwiftLanguageService {
  func retrieveRemoveUnusedParameterCodeActions(_ request: CodeActionRequest) async throws -> [CodeAction] {
    let snapshot = try await self.latestSnapshot(for: request.textDocument.uri)
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    guard let scope = SyntaxCodeActionScope(snapshot: snapshot, syntaxTree: syntaxTree, request: request) else {
      return []
    }

    guard let (parameter, parameterIndex, parameterClause, functionNamePosition) = findParameterAndContext(
      in: scope
    ) else {
      return []
    }

    let parameterName = (parameter.secondName ?? parameter.firstName).text
    guard !parameterName.isEmpty, parameterName != "_" else {
      return []
    }

    guard let body = findBody(of: parameterClause) else {
      return []
    }

    if parameterIsUsedInBody(parameterName: parameterName, body: body) {
      return []
    }

    var edits: [TextEdit] = []

    if let declEdit = buildDeclarationEdit(
      snapshot: snapshot,
      parameterClause: parameterClause,
      parameterIndex: parameterIndex
    ) {
      edits.append(declEdit)
    }

    let callSiteEdits = await buildCallSiteEdits(
      snapshot: snapshot,
      syntaxTree: syntaxTree,
      functionNamePosition: functionNamePosition,
      parameterIndex: parameterIndex,
      parameterLabel: parameter.firstName.text
    )
    edits.append(contentsOf: callSiteEdits)

    guard !edits.isEmpty else {
      return []
    }

    let title = "Remove unused parameter '\(parameterName)'"
    return [
      CodeAction(
        title: title,
        kind: .refactor,
        diagnostics: nil,
        edit: WorkspaceEdit(changes: [snapshot.uri: edits]),
        command: nil
      )
    ]
  }
}

// MARK: - Finding the parameter and declaration context

private func findParameterAndContext(
  in scope: SyntaxCodeActionScope
) -> (
  parameter: FunctionParameterSyntax,
  parameterIndex: Int,
  parameterClause: FunctionParameterClauseSyntax,
  functionNamePosition: AbsolutePosition
)? {
  guard let node = scope.innermostNodeContainingRange else {
    return nil
  }

  let parameter = node.findParentOfSelf(
    ofType: FunctionParameterSyntax.self,
    stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
  )
  guard let parameter else {
    return nil
  }

  guard let parameterList = parameter.parent?.as(FunctionParameterListSyntax.self),
    let parameterClause = parameterList.parent?.as(FunctionParameterClauseSyntax.self)
  else {
    return nil
  }

  guard let parameterIndex = parameterList.enumerated().first(where: { $0.element.id == parameter.id })?.offset
  else {
    return nil
  }

  guard let signature = parameterClause.parent?.as(FunctionSignatureSyntax.self) else {
    return nil
  }

  let functionNamePosition: AbsolutePosition
  switch signature.parent?.as(SyntaxEnum.self) {
  case .functionDecl(let functionDecl):
    functionNamePosition = functionDecl.name.positionAfterSkippingLeadingTrivia
  case .initializerDecl(let initializerDecl):
    functionNamePosition = initializerDecl.initKeyword.positionAfterSkippingLeadingTrivia
  default:
    return nil
  }

  return (parameter, parameterIndex, parameterClause, functionNamePosition)
}

private func findBody(of parameterClause: FunctionParameterClauseSyntax) -> CodeBlockSyntax? {
  guard let signature = parameterClause.parent?.as(FunctionSignatureSyntax.self) else {
    return nil
  }
  switch signature.parent?.as(SyntaxEnum.self) {
  case .functionDecl(let functionDecl):
    return functionDecl.body
  case .initializerDecl(let initializerDecl):
    return initializerDecl.body
  default:
    return nil
  }
}

// MARK: - Syntactic "unused" check

private func parameterIsUsedInBody(parameterName: String, body: CodeBlockSyntax) -> Bool {
  let visitor = DeclReferenceFinder(lookingFor: parameterName)
  visitor.walk(Syntax(body))
  return visitor.found
}

private final class DeclReferenceFinder: SyntaxVisitor {
  let targetName: String
  var found = false

  init(lookingFor name: String) {
    self.targetName = name
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if node.baseName.text == targetName {
      found = true
      return .skipChildren
    }
    return .visitChildren
  }
}

// MARK: - Declaration edit

private func buildDeclarationEdit(
  snapshot: DocumentSnapshot,
  parameterClause: FunctionParameterClauseSyntax,
  parameterIndex: Int
) -> TextEdit? {
  let parameters = parameterClause.parameters
  guard parameterIndex >= 0, parameterIndex < parameters.count else {
    return nil
  }

  var newParts: [String] = []
  for (index, param) in parameters.enumerated() {
    if index == parameterIndex {
      continue
    }
    let part = param.trimmedDescription
    // Strip trailing comma/space so we don't produce "(a: Int,)" when removing the last param.
    newParts.append(part.droppingTrailingCommaAndSpaces)
  }
  let newInner = newParts.joined(separator: ", ")
  let newText = "(\(newInner))"

  // Use end of right paren before trailing trivia so we don't remove the space before "{".
  let absoluteRange = parameterClause.position..<parameterClause.rightParen.endPositionBeforeTrailingTrivia
  let range = snapshot.absolutePositionRange(of: absoluteRange)
  return TextEdit(range: range, newText: newText)
}

// MARK: - Call site edits (same file)

private extension SwiftLanguageService {
  func buildCallSiteEdits(
    snapshot: DocumentSnapshot,
    syntaxTree: SourceFileSyntax,
    functionNamePosition: AbsolutePosition,
    parameterIndex: Int,
    parameterLabel: String
  ) async -> [TextEdit] {
    let functionNameLSPPosition = snapshot.position(of: functionNamePosition)
    let related: RelatedIdentifiersResponse
    do {
      related = try await self.relatedIdentifiers(
        at: functionNameLSPPosition,
        in: snapshot,
        includeNonEditableBaseNames: true
      )
    } catch {
      return []
    }

    let callRanges = related.relatedIdentifiers.filter { $0.usage == .call }.map(\.range)
    var edits: [TextEdit] = []
    for callRange in callRanges {
      guard let callEdit = removeArgumentAtCallSite(
        snapshot: snapshot,
        syntaxTree: syntaxTree,
        callRange: callRange,
        parameterIndex: parameterIndex,
        parameterLabel: parameterLabel
      ) else {
        continue
      }
      edits.append(callEdit)
    }
    return edits
  }
}

private func removeArgumentAtCallSite(
  snapshot: DocumentSnapshot,
  syntaxTree: SourceFileSyntax,
  callRange: Range<Position>,
  parameterIndex: Int,
  parameterLabel: String
) -> TextEdit? {
  let absolutePosition = snapshot.absolutePosition(of: callRange.lowerBound)
  guard let token = syntaxTree.token(at: absolutePosition) else {
    return nil
  }

  let callExpr: FunctionCallExprSyntax?
  if let ref = token.parent?.as(DeclReferenceExprSyntax.self),
    let parent = ref.parent,
    parent.is(FunctionCallExprSyntax.self)
  {
    callExpr = parent.as(FunctionCallExprSyntax.self)
  } else if let member = token.parent?.as(MemberAccessExprSyntax.self),
    let parent = member.parent,
    parent.is(FunctionCallExprSyntax.self)
  {
    callExpr = parent.as(FunctionCallExprSyntax.self)
  } else {
    return nil
  }

  guard let callExpr else {
    return nil
  }

  let arguments = callExpr.arguments
  guard parameterIndex < arguments.count else {
    return nil
  }

  let labeledExpr = arguments[arguments.index(arguments.startIndex, offsetBy: parameterIndex)]
  if labeledExpr.label?.text != parameterLabel {
    return nil
  }

  let absoluteRange: Range<AbsolutePosition>
  let isFirst = parameterIndex == 0
  let isLast = parameterIndex == arguments.count - 1

  if isFirst && isLast {
    absoluteRange = labeledExpr.position..<labeledExpr.endPosition
  } else if isFirst {
    let next = arguments[arguments.index(arguments.startIndex, offsetBy: parameterIndex + 1)]
    absoluteRange = labeledExpr.position..<next.position
  } else if isLast {
    // Include the comma before this argument so we don't leave "foo(a, )".
    let startOfRemoval: AbsolutePosition
    if let commaToken = labeledExpr.firstToken(viewMode: .sourceAccurate)?
      .previousToken(viewMode: .sourceAccurate),
      commaToken.tokenKind == .comma
    {
      startOfRemoval = commaToken.position
    } else {
      startOfRemoval = labeledExpr.position
    }
    absoluteRange = startOfRemoval..<labeledExpr.endPosition
  } else {
    let prev = arguments[arguments.index(arguments.startIndex, offsetBy: parameterIndex - 1)]
    let next = arguments[arguments.index(arguments.startIndex, offsetBy: parameterIndex + 1)]
    absoluteRange = prev.endPosition..<next.position
  }

  let rangeToRemove = snapshot.absolutePositionRange(of: absoluteRange)
  return TextEdit(range: rangeToRemove, newText: "")
}

// MARK: - Helpers

private extension String {
  /// Removes trailing comma and whitespace (e.g. "name: String, " -> "name: String").
  var droppingTrailingCommaAndSpaces: String {
    String(self.reversed().drop(while: { $0 == " " || $0 == "," }).reversed())
  }
}
