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

/// A code action that converts between `//` line comments and `/* */` block
/// comments.
///
/// Examples:
/// - Line to block:
///   ```
///   // This is a comment
///   // that spans multiple lines
///   ```
///   becomes:
///   ```
///   /* This is a comment
///      that spans multiple lines */
///   ```
///
/// - Block to line:
///   ```
///   /* This is a comment
///      that spans multiple lines */
///   ```
///   becomes:
///   ```
///   // This is a comment
///   // that spans multiple lines
///   ```
struct ConvertLineBlockComment: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let token = scope.innermostNodeContainingRange?.as(TokenSyntax.self)
        ?? scope.innermostNodeContainingRange?.firstToken(viewMode: .sourceAccurate) else {
      return []
    }

    // Check the previous token too, since comments might be in its trailing
    // trivia or the current token's leading trivia.
    var actions: [CodeAction] = []

    // Check leading trivia of the token for consecutive line comments.
    let leadingPieces = token.leadingTrivia.pieces
    let lineCommentRanges = findConsecutiveLineComments(in: leadingPieces)

    for range in lineCommentRanges {
      if let action = convertLineToBlock(
        pieces: leadingPieces,
        commentRange: range,
        token: token,
        scope: scope,
        isLeading: true
      ) {
        actions.append(action)
      }
    }

    // Check for block comments in leading trivia.
    for (index, piece) in leadingPieces.enumerated() {
      if case .blockComment(let text) = piece {
        if let action = convertBlockToLine(
          text: text,
          pieceIndex: index,
          token: token,
          scope: scope,
          isLeading: true,
          isDoc: false
        ) {
          actions.append(action)
        }
      }
    }

    return actions
  }

  /// Find ranges of consecutive line comment trivia pieces.
  private static func findConsecutiveLineComments(
    in pieces: [TriviaPiece]
  ) -> [Swift.Range<Int>] {
    var ranges: [Swift.Range<Int>] = []
    var start: Int? = nil

    for (i, piece) in pieces.enumerated() {
      switch piece {
      case .lineComment:
        if start == nil {
          start = i
        }
      case .newlines, .carriageReturns, .carriageReturnLineFeeds:
        // Newlines between line comments are expected.
        continue
      case .spaces, .tabs:
        // Indentation between comments is expected.
        continue
      default:
        if let s = start {
          // End the current range at the last line comment.
          let lastComment = pieces[s...i].lastIndex(where: {
            if case .lineComment = $0 { return true }
            return false
          })!
          ranges.append(s..<(lastComment + 1))
          start = nil
        }
      }
    }

    if let s = start {
      let lastComment = pieces[s...].lastIndex(where: {
        if case .lineComment = $0 { return true }
        return false
      })!
      ranges.append(s..<(lastComment + 1))
    }

    return ranges
  }

  /// Convert consecutive `//` line comments to a `/* */` block comment.
  private static func convertLineToBlock(
    pieces: [TriviaPiece],
    commentRange: Swift.Range<Int>,
    token: TokenSyntax,
    scope: SyntaxCodeActionScope,
    isLeading: Bool
  ) -> CodeAction? {
    // Extract the comment texts (stripping the leading //).
    var commentTexts: [String] = []
    for i in commentRange {
      if case .lineComment(let text) = pieces[i] {
        // Strip "// " or "//"
        var stripped = text.dropFirst(2)
        if stripped.hasPrefix(" ") {
          stripped = stripped.dropFirst()
        }
        commentTexts.append(String(stripped))
      }
    }

    guard !commentTexts.isEmpty else { return nil }

    // Determine indentation from the trivia before the first comment.
    let indentation = detectIndentation(pieces: pieces, before: commentRange.lowerBound)

    // Build the block comment.
    let blockComment: String
    if commentTexts.count == 1 {
      blockComment = "/* \(commentTexts[0]) */"
    } else {
      var lines = ["/*"]
      for text in commentTexts {
        lines.append(" \(text)")
      }
      lines.append(" */")
      blockComment = lines.joined(separator: "\n\(indentation)")
    }

    // Build new trivia: everything before the comment range, then the block
    // comment, then everything after.
    var newPieces: [TriviaPiece] = []
    // Keep pieces before the comment range.
    for i in 0..<commentRange.lowerBound {
      newPieces.append(pieces[i])
    }
    newPieces.append(.blockComment(blockComment))
    // Skip the original line comments and their interleaved newlines.
    var afterIndex = commentRange.upperBound
    // Skip trailing newline after the last comment.
    if afterIndex < pieces.count {
      switch pieces[afterIndex] {
      case .newlines, .carriageReturns, .carriageReturnLineFeeds:
        afterIndex += 1
      default:
        break
      }
    }
    for i in afterIndex..<pieces.count {
      newPieces.append(pieces[i])
    }

    let newTrivia = Trivia(pieces: newPieces)
    let newToken = token.with(\.leadingTrivia, newTrivia)

    let edit = TextEdit(
      range: Range(
        uncheckedBounds: (
          lower: scope.snapshot.position(of: token.position),
          upper: scope.snapshot.position(of: token.positionAfterSkippingLeadingTrivia)
        )
      ),
      newText: newToken.leadingTrivia.description
    )

    return CodeAction(
      title: "Convert to block comment",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
    )
  }

  /// Convert a `/* */` block comment to `//` line comments.
  private static func convertBlockToLine(
    text: String,
    pieceIndex: Int,
    token: TokenSyntax,
    scope: SyntaxCodeActionScope,
    isLeading: Bool,
    isDoc: Bool
  ) -> CodeAction? {
    // Parse the block comment content.
    var content = text.dropFirst(2)  // Remove /*
    guard content.hasSuffix("*/") else { return nil }
    content = content.dropLast(2)  // Remove */

    // Split into lines and strip common leading whitespace.
    let rawLines = content.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    let commentLines: [String] = rawLines.map { line in
      var trimmed = line
      // Remove leading/trailing whitespace per line.
      while trimmed.hasPrefix(" ") || trimmed.hasPrefix("\t") {
        trimmed.removeFirst()
      }
      while trimmed.hasSuffix(" ") || trimmed.hasSuffix("\t") {
        trimmed.removeLast()
      }
      return trimmed
    }.filter { !$0.isEmpty }

    guard !commentLines.isEmpty else { return nil }

    let pieces = token.leadingTrivia.pieces
    let indentation = detectIndentation(pieces: pieces, before: pieceIndex)

    // Build line comments.
    let lineComments = commentLines.map { "// \($0)" }
      .joined(separator: "\n\(indentation)")

    // Build new trivia.
    var newPieces: [TriviaPiece] = []
    for i in 0..<pieceIndex {
      newPieces.append(pieces[i])
    }

    // Add line comments as raw trivia pieces.
    let lineCommentPieces = parseLineCommentTrivia(lineComments, indentation: indentation)
    newPieces.append(contentsOf: lineCommentPieces)

    // Skip trailing whitespace/newline after the block comment.
    var afterIndex = pieceIndex + 1
    for i in afterIndex..<pieces.count {
      newPieces.append(pieces[i])
    }

    let newTrivia = Trivia(pieces: newPieces)
    let newToken = token.with(\.leadingTrivia, newTrivia)

    let edit = TextEdit(
      range: Range(
        uncheckedBounds: (
          lower: scope.snapshot.position(of: token.position),
          upper: scope.snapshot.position(of: token.positionAfterSkippingLeadingTrivia)
        )
      ),
      newText: newToken.leadingTrivia.description
    )

    return CodeAction(
      title: "Convert to line comments",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
    )
  }

  /// Detect indentation from trivia pieces before a given index.
  private static func detectIndentation(pieces: [TriviaPiece], before index: Int) -> String {
    // Look backwards for the last newline, then collect spaces/tabs after it.
    var indentation = ""
    for i in stride(from: index - 1, through: 0, by: -1) {
      switch pieces[i] {
      case .spaces(let count):
        indentation = String(repeating: " ", count: count) + indentation
      case .tabs(let count):
        indentation = String(repeating: "\t", count: count) + indentation
      case .newlines, .carriageReturns, .carriageReturnLineFeeds:
        return indentation
      default:
        return ""
      }
    }
    return indentation
  }

  /// Parse line comment text back into trivia pieces.
  private static func parseLineCommentTrivia(_ text: String, indentation: String) -> [TriviaPiece] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var pieces: [TriviaPiece] = []
    for (i, line) in lines.enumerated() {
      if i > 0 {
        pieces.append(.newlines(1))
        if !indentation.isEmpty {
          // Add indentation.
          let spaceCount = indentation.filter { $0 == " " }.count
          let tabCount = indentation.filter { $0 == "\t" }.count
          if tabCount > 0 {
            pieces.append(.tabs(tabCount))
          }
          if spaceCount > 0 {
            pieces.append(.spaces(spaceCount))
          }
        }
      }
      pieces.append(.lineComment(String(line)))
    }
    return pieces
  }
}
