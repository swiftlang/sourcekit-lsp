//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPLogging
import LanguageServerProtocol
import SourceKitD

/// A ranged token in the document used for syntax highlighting.
public struct SyntaxHighlightingToken: Hashable {
  /// The range of the token in the document. Must be on a single line.
  public var range: Range<Position> {
    didSet {
      assert(range.lowerBound.line == range.upperBound.line)
    }
  }
  /// The token type.
  public var kind: SemanticTokenTypes
  /// Additional metadata about the token.
  public var modifiers: SemanticTokenModifiers

  /// The (inclusive) start position of the token.
  public var start: Position { range.lowerBound }
  /// The (exclusive) end position of the token.
  public var end: Position { range.upperBound }
  /// The length of the token in UTF-16 code units.
  public var utf16length: Int { end.utf16index - start.utf16index }

  public init(range: Range<Position>, kind: SemanticTokenTypes, modifiers: SemanticTokenModifiers = []) {
    assert(range.lowerBound.line == range.upperBound.line)

    self.range = range
    self.kind = kind
    self.modifiers = modifiers
  }

  public init(start: Position, utf16length: Int, kind: SemanticTokenTypes, modifiers: SemanticTokenModifiers = []) {
    let range = start..<Position(line: start.line, utf16index: start.utf16index + utf16length)
    self.init(range: range, kind: kind, modifiers: modifiers)
  }
}

extension Array where Element == SyntaxHighlightingToken {
  /// The LSP representation of syntax highlighting tokens. Note that this
  /// requires the tokens in this array to be sorted.
  public var lspEncoded: [UInt32] {
    var previous = Position(line: 0, utf16index: 0)
    var rawTokens: [UInt32] = []
    rawTokens.reserveCapacity(count * 5)

    for token in self {
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
  /// preferring the given array's tokens if duplicate ranges are
  /// found.
  public func mergingTokens(with other: [SyntaxHighlightingToken]) -> [SyntaxHighlightingToken] {
    let otherRanges = Set(other.map(\.range))
    return filter { !otherRanges.contains($0.range) } + other
  }
}

extension SemanticTokenTypes {
  /// **(LSP Extension)**
  public static let identifier = Self("identifier")

  // LSP doesn’t know about actors. Display actors as classes.
  public static let actor = Self("class")

  /// All tokens supported by sourcekit-lsp
  public static let all: [Self] = predefined + [.identifier, .actor]

  /// Token types are looked up by index
  public var tokenType: UInt32 {
    UInt32(Self.all.firstIndex(of: self)!)
  }
}

extension SemanticTokenModifiers {
  /// All tokens supported by sourcekit-lsp
  public static let all: [Self] = predefined
}
