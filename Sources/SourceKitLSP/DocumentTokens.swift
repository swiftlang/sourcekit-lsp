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
import SwiftSyntax
import SwiftIDEUtils

/// Syntax highlighting tokens for a particular document.
public struct DocumentTokens {
  /// The syntax tree representing the entire document.
  public var syntaxTree: SourceFileSyntax?
  /// Semantic tokens, e.g. variable references, type references, ...
  public var semantic: [SyntaxHighlightingToken] = []
}

extension DocumentSnapshot {
  /// Computes an array of syntax highlighting tokens from the syntax tree that
  /// have been merged with any semantic tokens from SourceKit. If the provided
  /// range is non-empty, this function restricts its output to only those
  /// tokens whose ranges overlap it. If no range is provided, tokens for the
  /// entire document are returned.
  ///
  /// - Parameter range: The range of tokens to restrict this function to, if any.
  /// - Returns: An array of syntax highlighting tokens.
  public func mergedAndSortedTokens(in range: Range<Position>? = nil) -> [SyntaxHighlightingToken] {
    guard let tree = self.tokens.syntaxTree else {
      return self.tokens.semantic
    }
    let range = range.flatMap({ $0.byteSourceRange(in: self) })
             ?? ByteSourceRange(offset: 0, length: tree.byteSize)
    return tree
      .classifications(in: range)
      .flatMap({ $0.highlightingTokens(in: self) })
      .mergingTokens(with: self.tokens.semantic)
      .sorted { $0.start < $1.start }
  }
}

extension Range where Bound == Position {
  fileprivate func byteSourceRange(in snapshot: DocumentSnapshot) -> ByteSourceRange? {
    return snapshot.utf8OffsetRange(of: self).map({ ByteSourceRange(offset: $0.startIndex, length: $0.count) })
  }
}

extension SyntaxClassifiedRange {
  fileprivate func highlightingTokens(in snapshot: DocumentSnapshot) -> [SyntaxHighlightingToken] {
    guard let (kind, modifiers) = self.kind.highlightingKindAndModifiers else {
      return []
    }

    guard
      let start: Position = snapshot.positionOf(utf8Offset: self.offset),
      let end: Position = snapshot.positionOf(utf8Offset: self.endOffset)
    else {
      return []
    }

    let multiLineRange = start..<end
    let ranges = multiLineRange.splitToSingleLineRanges(in: snapshot)

    return ranges.map {
      SyntaxHighlightingToken(
        range: $0,
        kind: kind,
        modifiers: modifiers
      )
    }
  }
}

extension SyntaxClassification {
  fileprivate var highlightingKindAndModifiers: (SyntaxHighlightingToken.Kind, SyntaxHighlightingToken.Modifiers)? {
    switch self {
    case .none:
      return nil
    case .editorPlaceholder:
      return nil
    case .stringInterpolationAnchor:
      return nil
    case .keyword:
      return (.keyword, [])
    case .identifier, .typeIdentifier, .dollarIdentifier:
      return (.identifier, [])
    case .operatorIdentifier:
      return (.operator, [])
    case .integerLiteral, .floatingLiteral:
      return (.number, [])
    case .stringLiteral:
      return (.string, [])
    case .regexLiteral:
      return (.regexp, [])
    case .poundDirectiveKeyword:
      return (.macro, [])
    case .buildConfigId, .objectLiteral:
      return (.macro, [])
    case .attribute:
      return (.modifier, [])
    case .lineComment, .blockComment:
      return (.comment, [])
    case .docLineComment, .docBlockComment:
      return (.comment, .documentation)
    }
  }
}
