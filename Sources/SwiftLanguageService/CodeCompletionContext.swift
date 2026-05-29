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
  let followingCallContext: FollowingCallContext

  init(req: CompletionRequest, snapshot: DocumentSnapshot, tree: SourceFileSyntax) {
    self.cursorPosition = req.position
    self.identifierEndPosition = findEndOfIdentifier(position: req.position, snapshot: snapshot, tree: tree)
    self.followingCallContext = findFollowingCallContext(position: req.position, snapshot: snapshot, tree: tree)
  }
}

enum FollowingCallContext {
  case none
  case emptyParens(positionAfterClosingParen: Position)
  case nonEmptyParens
  case trailingClosure
}

private func findEndOfIdentifier(
  position: Position,
  snapshot: DocumentSnapshot,
  tree: SourceFileSyntax
) -> Position? {
  let token = tree.token(at: snapshot.absolutePosition(of: position))

  guard let token, case .identifier = token.tokenKind else {
    return nil
  }

  return snapshot.position(of: token.endPositionBeforeTrailingTrivia)
}

private func findIdentifierUnderCursor(
  position: Position,
  snapshot: DocumentSnapshot,
  tree: SourceFileSyntax
) -> TokenSyntax? {
  let absolutePosition = snapshot.absolutePosition(of: position)
  let token = tree.token(at: absolutePosition)
  guard let token else {
    return nil
  }

  // We also consider keywords here for cases where the user is trying to complete a function that also contains a
  // keyword in its name. If only the keyword part of the function name is typed, we still want to show the completion
  // for that function.
  // For example, if the user has a function `func selfTest()`, we want to show the completion for `selfTest` even if
  // the user has only typed `self` so far.
  if token.isIdentifierOrKeyword {
    return token
  }

  // If the cursor is right after an identifier, we also want to consider that identifier for completion.
  let previousToken = token.previousToken(viewMode: .sourceAccurate)
  guard let previousToken, previousToken.isIdentifierOrKeyword, previousToken.endPosition == absolutePosition else {
    return nil
  }

  return previousToken
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

private func findFollowingCallContext(
  position: Position,
  snapshot: DocumentSnapshot,
  tree: SourceFileSyntax
) -> FollowingCallContext {
  guard let identifier = findIdentifierUnderCursor(position: position, snapshot: snapshot, tree: tree),
    let parent = identifier.parent
  else {
    return .none
  }

  let functionCall: FunctionCallExprSyntax
  if let declReference = parent.as(DeclReferenceExprSyntax.self) {
    if let call = declReference.parent?.as(FunctionCallExprSyntax.self) {
      functionCall = call
    } else if let memberAccess = declReference.parent?.as(MemberAccessExprSyntax.self),
      let call = memberAccess.parent?.as(FunctionCallExprSyntax.self)
    {
      functionCall = call
    } else {
      return .none
    }
  } else if let macroExpansion = parent.as(MacroExpansionExprSyntax.self), let leftParen = macroExpansion.leftParen {
    return determineFollowingCallContextParenthesisKind(
      leftParen: leftParen,
      rightParen: macroExpansion.rightParen,
      snapshot: snapshot
    )
  } else {
    return .none
  }

  if let leftParen = functionCall.leftParen,
    // We don't want to report empty parentheses for code like this: `foo() { doSomethingInClosure() }` as that would
    // lead to the completion logic trying to replace the parentheses with the call argument labels
    functionCall.trailingClosure == nil
  {
    return determineFollowingCallContextParenthesisKind(
      leftParen: leftParen,
      rightParen: functionCall.rightParen,
      snapshot: snapshot
    )
  }

  // Braces on the next line are also parsed into a ClosureExprSyntax, so we need to ensure that the left brace is
  // actually on the same line as the cursor to consider it a trailing closure context.
  if let trailingClosure = functionCall.trailingClosure,
    snapshot.position(of: trailingClosure.leftBrace.positionAfterSkippingLeadingTrivia).line == position.line
  {
    return .trailingClosure
  }

  return .none
}

private func determineFollowingCallContextParenthesisKind(
  leftParen: TokenSyntax,
  rightParen: TokenSyntax?,
  snapshot: DocumentSnapshot
) -> FollowingCallContext {
  if let rightParen, leftParen.nextToken(viewMode: .sourceAccurate) == rightParen,
    // Only actually consider the parens as empty if there is no comment or newline in between. A comment should not be
    // overwrittten and replacing parens across multiple lines is likely not what the user intended.
    !leftParen.trailingTrivia.contains(where: { $0.isComment || $0.isNewline }),
    !rightParen.leadingTrivia.contains(where: { $0.isComment || $0.isNewline })
  {
    return .emptyParens(positionAfterClosingParen: snapshot.position(of: rightParen.endPositionBeforeTrailingTrivia))
  } else {
    return .nonEmptyParens
  }
}
