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

import Foundation
@_spi(RawSyntax) @_spi(SwiftSyntax) import SwiftSyntax

/// SyntaxRewriter that removes indentation for lines starting with a newline.
class IndentationRemover: SyntaxRewriter {
  private let indentation: [TriviaPiece]
  private var shouldUnindent: Bool

  init(indentation: Trivia, indentFirstLine: Bool = false) {
    self.indentation = indentation.decomposed.pieces
    self.shouldUnindent = indentFirstLine
    super.init(viewMode: .sourceAccurate)
  }

  private func unindentAfterNewlines(_ content: String) -> String {
    let lines = content.components(separatedBy: .newlines)
    var result: [String] = []

    if let first = lines.first {
      result.append(first)
    }

    let pattern = Trivia(pieces: indentation).description
    for line in lines.dropFirst() {
      if line.hasPrefix(pattern) {
        result.append(String(line.dropFirst(pattern.count)))
      } else {
        result.append(line)
      }
    }
    return result.joined(separator: "\n")
  }

  private func unindent(_ trivia: Trivia) -> Trivia {
    var result: [TriviaPiece] = []
    result.reserveCapacity(trivia.count)

    var remainingPieces = trivia.decomposed.pieces
    while let piece = remainingPieces.first {
      remainingPieces.removeFirst()
      switch piece {
      case .newlines, .carriageReturns, .carriageReturnLineFeeds:
        shouldUnindent = true
        result.append(piece)
      case .blockComment(let content):
        result.append(.blockComment(unindentAfterNewlines(content)))
      case .docBlockComment(let content):
        result.append(.docBlockComment(unindentAfterNewlines(content)))
      case .unexpectedText(let content):
        result.append(.unexpectedText(unindentAfterNewlines(content)))
      default:
        result.append(piece)
      }

      if shouldUnindent {
        if remainingPieces.starts(with: indentation) {
          remainingPieces.removeFirst(indentation.count)
        }
        shouldUnindent = false
      }
    }
    shouldUnindent = false
    return Trivia(pieces: result)
  }

  override func visit(_ token: TokenSyntax) -> TokenSyntax {
    let indentedLeadingTrivia = unindent(token.leadingTrivia)

    if case .stringSegment(let content) = token.tokenKind,
      let last = content.last,
      last.isNewline
    {
      shouldUnindent = true
    }

    return
      token
      .with(\.leadingTrivia, indentedLeadingTrivia)
      .with(\.trailingTrivia, unindent(token.trailingTrivia))
  }
}
