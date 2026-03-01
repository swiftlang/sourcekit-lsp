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
import SKOptions
import SourceKitLSP
import SwiftRefactor
import SwiftSyntax

/// Describes types that provide one or more code actions based on purely
/// syntactic information.
protocol SyntaxCodeActionProvider: SendableMetatype {
  /// Produce code actions within the given scope. Each code action
  /// corresponds to one syntactic transformation that can be performed, such
  /// as adding or removing separators from an integer literal.
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction]
}

/// Defines the scope in which a syntactic code action occurs.
struct SyntaxCodeActionScope {
  /// The snapshot of the document on which the code actions will be evaluated.
  var snapshot: DocumentSnapshot

  /// The actual code action request, which can specify additional parameters
  /// to guide the code actions.
  var request: CodeActionRequest

  /// The source file in which the syntactic code action will operate.
  var file: SourceFileSyntax

  /// The UTF-8 byte range in the source file in which code actions should be
  /// considered, i.e., where the cursor or selection is.
  var range: Range<AbsolutePosition>

  /// The innermost node that contains the entire selected source range
  var innermostNodeContainingRange: Syntax?

  /// Options for file header code action, if available.
  var fileHeaderOptions: SourceKitLSPOptions.FileHeaderOptions?

  init?(
    snapshot: DocumentSnapshot,
    syntaxTree file: SourceFileSyntax,
    request: CodeActionRequest,
    fileHeaderOptions: SourceKitLSPOptions.FileHeaderOptions? = nil
  ) {
    self.snapshot = snapshot
    self.request = request
    self.file = file
    self.fileHeaderOptions = fileHeaderOptions

    guard let left = tokenForRefactoring(at: request.range.lowerBound, snapshot: snapshot, syntaxTree: file),
      let right = tokenForRefactoring(at: request.range.upperBound, snapshot: snapshot, syntaxTree: file)
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
