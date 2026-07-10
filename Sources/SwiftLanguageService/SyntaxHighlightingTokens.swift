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

  /// Syntax highlighting tokens sorted by their start position.
  package let tokens: [SyntaxHighlightingToken]

  /// Creates a syntax highlighting token collection from an sorted array.
  ///
  /// - Parameter sortedTokens: Syntax highlighting tokens sorted by their start position.
  package init(sortedTokens: [SyntaxHighlightingToken]) {
    assert(
      zip(sortedTokens, sortedTokens.dropFirst()).allSatisfy { $0.start <= $1.start },
      "Tokens must always be sorted by their start position"
    )
    self.tokens = sortedTokens
  }

  /// Creates a syntax highlighting token collection from a potentially unsorted array.
  ///
  /// - Parameter tokens: Syntax highlighting tokens that will be sorted by their start position.
  package init(tokens: [SyntaxHighlightingToken]) {
    self.init(sortedTokens: tokens.sorted { $0.start < $1.start })
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
    var merged: [SyntaxHighlightingToken] = []
    merged.reserveCapacity(tokens.count + other.tokens.count)

    var selfIterator = tokens.makeIterator()
    var otherIterator = other.tokens.makeIterator()

    var currentToken = selfIterator.next()
    var currentOtherToken = otherIterator.next()

    while let token = currentToken, let otherToken = currentOtherToken {
      if token.range.overlaps(otherToken.range) {
        currentToken = selfIterator.next()
      } else if token.start < otherToken.start {
        merged.append(token)
        currentToken = selfIterator.next()
      } else {
        merged.append(otherToken)
        currentOtherToken = otherIterator.next()
      }
    }

    while let token = currentToken {
      merged.append(token)
      currentToken = selfIterator.next()
    }

    while let otherToken = currentOtherToken {
      merged.append(otherToken)
      currentOtherToken = otherIterator.next()
    }

    return SyntaxHighlightingTokens(sortedTokens: merged)
  }
}

extension SyntaxHighlightingTokens {
  /// Decodes the LSP representation of syntax highlighting tokens
  package init(lspEncodedTokens rawTokens: [UInt32]) {
    assert(rawTokens.count.isMultiple(of: 5))
    var parsedTokens: [SyntaxHighlightingToken] = []
    parsedTokens.reserveCapacity(rawTokens.count / 5)

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

      parsedTokens.append(
        SyntaxHighlightingToken(
          start: current,
          utf16length: length,
          kind: kind,
          modifiers: modifiers
        )
      )
    }
    self.init(sortedTokens: parsedTokens)
  }
}
