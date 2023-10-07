//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import LSPLogging
import SwiftSyntax
import SwiftIDEUtils
import SwiftParser

extension SwiftLanguageServer {
  /// Computes an array of syntax highlighting tokens from the syntax tree that
  /// have been merged with any semantic tokens from SourceKit. If the provided
  /// range is non-empty, this function restricts its output to only those
  /// tokens whose ranges overlap it. If no range is provided, tokens for the
  /// entire document are returned.
  ///
  /// - Parameter range: The range of tokens to restrict this function to, if any.
  /// - Returns: An array of syntax highlighting tokens.
  private func mergedAndSortedTokens(
    for snapshot: DocumentSnapshot,
    in range: Range<Position>? = nil
  ) async -> [SyntaxHighlightingToken] {
    let tree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let semanticTokens = await semanticTokensManager.semanticTokens(for: snapshot.id)
    let range = range.flatMap({ $0.byteSourceRange(in: snapshot) })
             ?? ByteSourceRange(offset: 0, length: tree.totalLength.utf8Length)
    return tree
      .classifications(in: range)
      .flatMap({ $0.highlightingTokens(in: snapshot) })
      .mergingTokens(with: semanticTokens ?? [])
      .sorted { $0.start < $1.start }
  }

  public func documentSemanticTokens(_ req: DocumentSemanticTokensRequest) async throws -> DocumentSemanticTokensResponse? {
    let uri = req.textDocument.uri

    guard let snapshot = self.documentManager.latestSnapshot(uri) else {
      log("failed to find snapshot for uri \(uri)")
      return DocumentSemanticTokensResponse(data: [])
    }

    let tokens = await mergedAndSortedTokens(for: snapshot)
    let encodedTokens = tokens.lspEncoded

    return DocumentSemanticTokensResponse(data: encodedTokens)
  }

  public func documentSemanticTokensDelta(_ req: DocumentSemanticTokensDeltaRequest) async throws -> DocumentSemanticTokensDeltaResponse? {
    return nil
  }

  public func documentSemanticTokensRange(_ req: DocumentSemanticTokensRangeRequest) async throws -> DocumentSemanticTokensResponse? {
    let uri = req.textDocument.uri
    let range = req.range

    guard let snapshot = self.documentManager.latestSnapshot(uri) else {
      log("failed to find snapshot for uri \(uri)")
      return DocumentSemanticTokensResponse(data: [])
    }

    let tokens = await mergedAndSortedTokens(for: snapshot, in: range)
    let encodedTokens = tokens.lspEncoded

    return DocumentSemanticTokensResponse(data: encodedTokens)
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
    case .keyword:
      return (.keyword, [])
    case .identifier, .type, .dollarIdentifier:
      return (.identifier, [])
    case .operator:
      return (.operator, [])
    case .integerLiteral, .floatLiteral:
      return (.number, [])
    case .stringLiteral:
      return (.string, [])
    case .regexLiteral:
      return (.regexp, [])
    case .ifConfigDirective:
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
