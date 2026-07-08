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
import SourceKitD
import SourceKitLSP

/// A wrapper around an array of syntax highlighting tokens.
package struct SyntaxHighlightingTokens: Sendable {
  package var tokens: [SyntaxHighlightingToken]

  package init(tokens: [SyntaxHighlightingToken]) {
    self.tokens = tokens
  }

  /// The LSP representation of syntax highlighting tokens. Note that this
  /// requires the tokens in this array to be sorted.
  package var lspEncoded: [UInt32] {
    var previous = Position(line: 0, utf16index: 0)
    var rawTokens: [UInt32] = []
    rawTokens.reserveCapacity(tokens.count * 5)

    for token in self.tokens {
      let lineDelta = token.start.line - previous.line
      let charDelta =
        token.start.utf16index - (
          // The character delta is relative to the previous token's start
          // only if the token is on the previous token's line.
          previous.line == token.start.line ? previous.utf16index : 0)

      // We assert that the tokens are actually sorted
      assert(lineDelta >= 0)
      assert(charDelta >= 0)

      previous = token.start
      rawTokens += [
        UInt32(lineDelta),
        UInt32(charDelta),
        UInt32(token.utf16length),
        token.kind.tokenType,
        token.modifiers.rawValue,
      ]
    }

    return rawTokens
  }

  /// Merges the tokens in this array into a new token array,
  /// preferring the given array's tokens if overlapping ranges are
  /// found.
  package func mergingTokens(with other: SyntaxHighlightingTokens) -> SyntaxHighlightingTokens {
    return self.mergingTokens(with: other.tokens)
  }

  package func mergingTokens(with other: [SyntaxHighlightingToken]) -> SyntaxHighlightingTokens {
    var filteredTokens: [SyntaxHighlightingToken] = []
    filteredTokens.reserveCapacity(tokens.count)

    var selfIndex = 0
    var otherIndex = 0

    while selfIndex < tokens.count && otherIndex < other.count {
      let token = tokens[selfIndex]
      let otherToken = other[otherIndex]

      if otherToken.range.upperBound <= token.range.lowerBound {
        otherIndex += 1
      } else if token.range.upperBound <= otherToken.range.lowerBound {
        filteredTokens.append(token)
        selfIndex += 1
      } else {
        let tokenRange = token.range
        let otherRange = otherToken.range

        let syntacticEnclosesSemantic = tokenRange.lowerBound <= otherRange.lowerBound && tokenRange.upperBound >= otherRange.upperBound
        let semanticEnclosesSyntactic = otherRange.lowerBound <= tokenRange.lowerBound && otherRange.upperBound >= tokenRange.upperBound

        if syntacticEnclosesSemantic || semanticEnclosesSyntactic {
          selfIndex += 1
        } else {
          if tokenRange.upperBound <= otherRange.upperBound {
            filteredTokens.append(token)
            selfIndex += 1
          } else {
            otherIndex += 1
          }
        }
      }
    }

    if selfIndex < tokens.count {
      filteredTokens.append(contentsOf: tokens[selfIndex...])
    }

    return SyntaxHighlightingTokens(tokens: filteredTokens + other)
  }

  /// Sorts the tokens in this array by their start position.
  package func sorted(
    _ areInIncreasingOrder: (SyntaxHighlightingToken, SyntaxHighlightingToken) -> Bool
  ) -> SyntaxHighlightingTokens {
    SyntaxHighlightingTokens(tokens: tokens.sorted(by: areInIncreasingOrder))
  }
}

extension SyntaxHighlightingTokens {
  /// Decodes the LSP representation of syntax highlighting tokens
  package init(lspEncodedTokens rawTokens: [UInt32]) {
    self.init(tokens: [])
    assert(rawTokens.count.isMultiple(of: 5))
    self.tokens.reserveCapacity(rawTokens.count / 5)

    var current = Position(line: 0, utf16index: 0)

    for i in stride(from: 0, to: rawTokens.count, by: 5) {
      let lineDelta = Int(rawTokens[i])
      let charDelta = Int(rawTokens[i + 1])
      let length = Int(rawTokens[i + 2])
      let rawKind = rawTokens[i + 3]
      let rawModifiers = rawTokens[i + 4]

      current.line += lineDelta

      if lineDelta == 0 {
        current.utf16index += charDelta
      } else {
        current.utf16index = charDelta
      }

      let kind = SemanticTokenTypes.all[Int(rawKind)]
      let modifiers = SemanticTokenModifiers(rawValue: rawModifiers)

      self.tokens.append(
        SyntaxHighlightingToken(
          start: current,
          utf16length: length,
          kind: kind,
          modifiers: modifiers
        )
      )
    }
  }
}
