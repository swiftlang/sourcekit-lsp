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

@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftIDEUtils
import SwiftParser
import SwiftSyntax

extension SwiftLanguageService {
  /// Requests the semantic highlighting tokens for the given snapshot from sourcekitd.
  private func semanticHighlightingTokens(for snapshot: DocumentSnapshot) async throws -> SyntaxHighlightingTokens? {
    guard let compileCommand = await self.compileCommand(for: snapshot.uri, fallbackAfterTimeout: false),
      !compileCommand.isFallback
    else {
      return nil
    }

    let skreq = sourcekitd.dictionary([
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compileCommand.compilerArgs as [any SKDRequestValue],
    ])

    let dict = try await send(sourcekitdRequest: \.semanticTokens, skreq, snapshot: snapshot)

    guard let skTokens: SKDResponseArray = dict[keys.semanticTokens] else {
      return nil
    }

    try Task.checkCancellation()

    return SyntaxHighlightingTokenParser(sourcekitd: sourcekitd).parseTokens(skTokens, in: snapshot)
  }

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
  ) async throws -> SyntaxHighlightingTokens {
    try Task.checkCancellation()

    async let tree = syntaxTreeManager.syntaxTree(for: snapshot)
    let semanticTokens = await orLog("Loading semantic tokens") { try await semanticHighlightingTokens(for: snapshot) }

    let range =
      if let range {
        snapshot.byteSourceRange(of: range)
      } else {
        await tree.range
      }

    try Task.checkCancellation()

    let tokens =
      await tree
      .classifications(in: range)
      .map { $0.highlightingTokens(in: snapshot) }
      .reduce(into: SyntaxHighlightingTokens(tokens: [])) { $0.tokens += $1.tokens }

    try Task.checkCancellation()

    return
      tokens
      .mergingTokens(with: semanticTokens ?? SyntaxHighlightingTokens(tokens: []))
      .sorted { $0.start < $1.start }
  }

  package func documentSemanticTokens(
    _ req: DocumentSemanticTokensRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    let snapshot = try await self.latestSnapshot(for: req.textDocument.uri)

    let tokens = try await mergedAndSortedTokens(for: snapshot)
    let encodedTokens = tokens.lspEncoded

    return DocumentSemanticTokensResponse(data: encodedTokens)
  }

  package func documentSemanticTokensDelta(
    _ req: DocumentSemanticTokensDeltaRequest
  ) async throws -> DocumentSemanticTokensDeltaResponse? {
    return nil
  }

  package func documentSemanticTokensRange(
    _ req: DocumentSemanticTokensRangeRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)
    let tokens = try await mergedAndSortedTokens(for: snapshot, in: req.range)
    let encodedTokens = tokens.lspEncoded

    return DocumentSemanticTokensResponse(data: encodedTokens)
  }
}

extension SyntaxClassifiedRange {
  fileprivate func highlightingTokens(in snapshot: DocumentSnapshot) -> SyntaxHighlightingTokens {
    guard let (kind, modifiers) = self.kind.highlightingKindAndModifiers else {
      return SyntaxHighlightingTokens(tokens: [])
    }

    let multiLineRange = snapshot.absolutePositionRange(of: self.range)
    let ranges = multiLineRange.splitToSingleLineRanges(in: snapshot)

    let tokens = ranges.map {
      SyntaxHighlightingToken(
        range: $0,
        kind: kind,
        modifiers: modifiers
      )
    }

    return SyntaxHighlightingTokens(tokens: tokens)
  }
}

extension SyntaxClassification {
  fileprivate var highlightingKindAndModifiers: (SemanticTokenTypes, SemanticTokenModifiers)? {
    switch self {
    case .none:
      return nil
    case .editorPlaceholder:
      return nil
    case .keyword:
      return nil
    case .identifier, .type, .dollarIdentifier:
      return (.identifier, [])
    case .operator:
      return nil
    case .integerLiteral, .floatLiteral:
      return nil
    case .stringLiteral:
      return nil
    case .regexLiteral:
      return nil
    case .ifConfigDirective:
      return nil
    case .attribute:
      return (.modifier, [])
    case .lineComment, .blockComment:
      return nil
    case .docLineComment, .docBlockComment:
      return nil
    case .argumentLabel:
      return nil
    #if RESILIENT_LIBRARIES
    @unknown default:
      fatalError("Unknown case")
    #endif
    }
  }
}
