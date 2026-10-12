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

@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
package import SourceKitLSP
import SwiftRefactor
package import SwiftSyntax

/// Data that is included in a `CodeAction` response for which the client should resolve the edit lazily using a `codeAction/resolve` request.
///
/// This data allows us to re-construct the `SyntaxCodeActionScope`.
package struct UnresolvedCodeActionData: Codable, LSPAnyCodable {
  /// A string representation of the syntax refactoring action's type.
  package let action: String

  /// The document on which the code action should be applied.
  package let document: VersionedTextDocumentIdentifier

  /// The range at which the code action was originally requested.
  package let range: Range<Position>

  /// Action-specific data describing what data needs to be resolved asynchronously during the resolve request.
  package let data: LSPAny

  init<Metatype: ResolvableSyntaxRefactoringCodeActionProvider>(
    actionType: Metatype.Type,
    document: VersionedTextDocumentIdentifier,
    range: Range<Position>,
    data: LSPAny
  ) {
    self.action = "\(Metatype.self)"
    self.document = document
    self.range = range
    self.data = data
  }
}

/// Describes types that provide one or more code actions based on purely
/// syntactic information.
package protocol SyntaxCodeActionProvider: SendableMetatype {
  /// Produce code actions within the given scope. Each code action
  /// corresponds to one syntactic transformation that can be performed, such
  /// as adding or removing separators from an integer literal.
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction]

  /// Resolve semantic information for a code action.
  static func resolve(
    _ codeAction: CodeAction,
    in scope: SyntaxCodeActionScope,
    unresolvedData: LSPAny,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> CodeAction
}

extension SyntaxCodeActionProvider {
  package static func resolve(
    _ codeAction: CodeAction,
    in scope: SyntaxCodeActionScope,
    unresolvedData: LSPAny,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> CodeAction {
    return codeAction
  }
}

extension TextDocumentClientCapabilities.CodeAction.ResolveSupportProperties {
  var canResolveEdit: Bool {
    return self.properties.contains("edit")
  }
}

/// Defines the scope in which a syntactic code action occurs.
package struct SyntaxCodeActionScope {
  /// Whether the client supports the codeAction/resolve request.
  ///
  /// This allows code actions to use a syntactic fallback if semantic information cannot be resolved using the `codeAction/resolve` request.
  package var resolveSupport: TextDocumentClientCapabilities.CodeAction.ResolveSupportProperties?

  /// The snapshot of the document on which the code actions will be evaluated.
  package var snapshot: DocumentSnapshot

  /// The source file in which the syntactic code action will operate.
  package var file: SourceFileSyntax

  /// The originally requested range in the original code action request.
  ///
  /// Generally, `range` should be preferred because it performs useful adjustments to extend the range to the start and end of tokens.
  var requestedRange: Range<Position>

  /// The UTF-8 byte range in the source file in which code actions should be
  /// considered, i.e., where the cursor or selection is.
  package var range: Range<AbsolutePosition>

  /// The innermost node that contains the entire selected source range
  package var innermostNodeContainingRange: Syntax?

  package init?(
    resolveSupport: TextDocumentClientCapabilities.CodeAction.ResolveSupportProperties?,
    snapshot: DocumentSnapshot,
    syntaxTree file: SourceFileSyntax,
    requestedRange: Range<Position>,
  ) {
    self.resolveSupport = resolveSupport
    self.snapshot = snapshot
    self.requestedRange = requestedRange
    self.file = file

    guard let left = tokenForRefactoring(at: requestedRange.lowerBound, snapshot: snapshot, syntaxTree: file),
      let right = tokenForRefactoring(at: requestedRange.upperBound, snapshot: snapshot, syntaxTree: file)
    else {
      return nil
    }
    self.range = left.position..<right.endPosition
    self.innermostNodeContainingRange = findCommonAncestorOrSelf(Syntax(left), Syntax(right))
  }
}

private func tokenForRefactoring(
  at position: Position,
  snapshot: DocumentSnapshot,
  syntaxTree: SourceFileSyntax
) -> TokenSyntax? {
  let absolutePosition = snapshot.absolutePosition(of: position)
  if absolutePosition == syntaxTree.endPosition {
    // token(at:) will not find the end of file token if the end of file token has length 0. Special case this and
    // return the last proper token in this case.
    return syntaxTree.endOfFileToken.previousToken(viewMode: .sourceAccurate)
  }
  guard let token = syntaxTree.token(at: absolutePosition) else {
    return nil
  }
  // See `adjustPositionToStartOfIdentifier`. We need to be a little more aggressive for the refactorings and also
  // adjust to the start of punctuation eg. if the end of the selected range is after a `}`, we want the end token for
  // the refactoring to be the `}`, not the token after `}`.
  if absolutePosition == token.position,
    let previousToken = token.previousToken(viewMode: .sourceAccurate),
    previousToken.endPositionBeforeTrailingTrivia == absolutePosition
  {
    return previousToken
  }
  return token
}
