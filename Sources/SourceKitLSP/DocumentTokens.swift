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

import LanguageServerProtocol

/// Syntax highlighting tokens for a particular document.
public struct DocumentTokens {
  /// Lexical tokens, e.g. keywords, raw identifiers, ...
  public var lexical: [SyntaxHighlightingToken] = []
  /// Semantic tokens, e.g. variable references, type references, ...
  public var semantic: [SyntaxHighlightingToken] = []

  private var merged: [SyntaxHighlightingToken] {
    lexical.mergingTokens(with: semantic)
  }
  public var mergedAndSorted: [SyntaxHighlightingToken] {
    merged.sorted { $0.start < $1.start }
  }

  /// Modifies the syntax highlighting tokens of each kind
  /// (lexical and semantic) according to `action`.
  public mutating func withMutableTokensOfEachKind(_ action: (inout [SyntaxHighlightingToken]) -> Void) {
    action(&lexical)
    action(&semantic)
  }

  // Replace all lexical tokens in `range`.
  public mutating func replaceLexical(in range: Range<Position>, with newTokens: [SyntaxHighlightingToken]) {
    lexical.removeAll { $0.range.overlaps(range) }
    lexical += newTokens
  }
}
