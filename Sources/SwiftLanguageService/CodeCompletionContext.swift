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

struct CompletionRequestContext {
  let cursorPosition: Position
  /// If the completion is triggered in the middle of an identifier, this is the position after the end of the
  /// identifier. This is needed to compute the correct text edit for completions that replace an existing identifier.
  let identifierEndPosition: Position?

  init(req: CompletionRequest, snapshot: DocumentSnapshot, tree: SourceFileSyntax) {
    self.cursorPosition = req.position
    self.identifierEndPosition = findEndOfIdentifier(position: req.position, snapshot: snapshot, tree: tree)
  }
}

private func findEndOfIdentifier(
  position: Position,
  snapshot: DocumentSnapshot,
  tree: SourceFileSyntax
) -> Position? {
  let token = tree.token(at: snapshot.absolutePosition(of: position))

  guard let token, token.isIdentifierOrKeyword else {
    return nil
  }

  return snapshot.position(of: token.endPositionBeforeTrailingTrivia)
}

private extension TokenSyntax {
  var isIdentifierOrKeyword: Bool {
    switch tokenKind {
    case .identifier, .keyword:
      return true
    default:
      return false
    }
  }
}
