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

@_spi(RawSyntax) import SwiftSyntax
import SwiftSyntaxBuilder

final class DeclModifierRemover: SyntaxRewriter {
  private let predicate: (DeclModifierSyntax) -> Bool

  private var triviaToAttachToNextToken: Trivia = Trivia()

  /// Initializes a modifier remover with a given predicate to determine which modifiers to remove.
  ///
  /// - Parameter predicate: A closure that determines whether a given `AttributeSyntax` should be removed.
  ///   If this closure returns `true` for an attribute, that attribute will be removed.
  init(removingWhere predicate: @escaping (DeclModifierSyntax) -> Bool) {
    self.predicate = predicate
    super.init()
  }

  override func visit(_ node: DeclModifierListSyntax) -> DeclModifierListSyntax {
    var filteredModifiers: [DeclModifierListSyntax.Element] = []

    for modifier in node {
      guard self.predicate(modifier) else {
        filteredModifiers.append(prependAndClearAccumulatedTrivia(to: modifier))
        continue
      }

      // Removing modifier before comment leaves space before comment intact — doesn’t merge with following trivia.
      let trailingTrivia = Trivia(pieces: modifier.trailingTrivia.trimmingPrefix(while: \.isSpaceOrTab))
      triviaToAttachToNextToken += modifier.leadingTrivia.merging(trailingTrivia)
    }

    if !triviaToAttachToNextToken.isEmpty, !filteredModifiers.isEmpty {
      filteredModifiers[filteredModifiers.count - 1].trailingTrivia = filteredModifiers[filteredModifiers.count - 1]
        .trailingTrivia
        .merging(triviaToAttachToNextToken)
      triviaToAttachToNextToken = Trivia()
    }

    return DeclModifierListSyntax(filteredModifiers)
  }

  override func visit(_ token: TokenSyntax) -> TokenSyntax {
    return prependAndClearAccumulatedTrivia(to: token)
  }

  /// Prepends the accumulated trivia to the given node's leading trivia.
  ///
  /// To preserve correct formatting after attribute removal, this function reassigns
  /// significant trivia accumulated from removed attributes to the provided subsequent node.
  /// Once attached, the accumulated trivia is cleared.
  ///
  /// - Parameter node: The syntax node receiving the accumulated trivia.
  /// - Returns: The modified syntax node with the prepended trivia.
  private func prependAndClearAccumulatedTrivia<T: SyntaxProtocol>(to syntaxNode: T) -> T {
    guard !triviaToAttachToNextToken.isEmpty else { return syntaxNode }
    defer { triviaToAttachToNextToken = Trivia() }
    return syntaxNode.with(\.leadingTrivia, triviaToAttachToNextToken.merging(syntaxNode.leadingTrivia))
  }
}
