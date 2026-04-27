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
@_spi(SourceKitLSP) import SKLogging
import SourceKitLSP
import SwiftRefactor
import SwiftSyntax

extension TextDocumentClientCapabilities.CodeAction.ResolveSupportProperties {
  var canResolveEdit: Bool {
    return self.properties.contains("edit")
  }
}

/// Describes types that provide one or more code actions based on purely
/// syntactic information.
protocol SyntaxCodeActionProvider: SendableMetatype {
  /// Produce code actions within the given scope. Each code action
  /// corresponds to one syntactic transformation that can be performed, such
  /// as adding or removing separators from an integer literal.
  static func codeActions(in scope: SyntaxCodeActionScope) async -> [CodeAction]
}

/// Defines the scope in which a syntactic code action occurs.
struct SyntaxCodeActionScope {
  /// Whether the client supports the codeAction/resolve request.
  ///
  /// This is set to `nil` during the `codeAction/resolve` request.
  var resolveSupport: TextDocumentClientCapabilities.CodeAction.ResolveSupportProperties?

  /// The snapshot of the document on which the code actions will be evaluated.
  var snapshot: DocumentSnapshot

  /// The source file in which the syntactic code action will operate.
  var file: SourceFileSyntax

  /// The originally requested range in the original code action request.
  ///
  /// Generally, `range` should be preferred because it performs useful adjustments to extend the range to the start and end of tokens.
  var requestedRange: Range<Position>

  /// The UTF-8 byte range in the source file in which code actions should be
  /// considered, i.e., where the cursor or selection is.
  var range: Range<AbsolutePosition>

  /// The innermost node that contains the entire selected source range
  var innermostNodeContainingRange: Syntax?

  /// The language service from which this code action is going to be resolved.
  ///
  /// Used to to retrieve cursor info if necessary.
  private let swiftLanguageService: SwiftLanguageService

  init?(
    resolveSupport: TextDocumentClientCapabilities.CodeAction.ResolveSupportProperties?,
    snapshot: DocumentSnapshot,
    syntaxTree file: SourceFileSyntax,
    requestedRange: Range<Position>,
    swiftLanguageService: SwiftLanguageService
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
    self.swiftLanguageService = swiftLanguageService
  }

  /// Retrieve the cursor info in the code action's document at the given position.
  ///
  /// Because this can be an expensive operation, this should only be called after all syntactic checks and if the request does not support lazily
  /// resolving of the `edit` properties.
  func cursorInfo(at position: Position) async throws -> [CursorInfo] {
    let compileCommand = await swiftLanguageService.compileCommand(
      for: snapshot.uri,
      fallbackAfterTimeout: true
    )

    return try await swiftLanguageService.cursorInfo(
      snapshot,
      compileCommand: compileCommand,
      position..<position
    ).cursorInfo
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
