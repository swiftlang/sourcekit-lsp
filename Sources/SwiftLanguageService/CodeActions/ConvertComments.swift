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

/// Syntactic code action provider to convert between `//` line comments and
/// `/* ... */` block comments.
struct ConvertComments: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    // Find the token that contains or is adjacent to the selection
    guard let token = scope.file.token(at: scope.range.lowerBound) else {
      return []
    }

    // Check leading trivia of the token (comments typically appear here)
    if let action = codeAction(
      for: token.leadingTrivia,
      startPosition: token.position,
      scope: scope
    ) {
      return [action]
    }

    // Also check trailing trivia of the previous token
    if let previousToken = token.previousToken(viewMode: .sourceAccurate) {
      if let action = codeAction(
        for: previousToken.trailingTrivia,
        startPosition: previousToken.endPositionBeforeTrailingTrivia,
        scope: scope
      ) {
        return [action]
      }
    }

    return []
  }

  private static func codeAction(
    for trivia: Trivia,
    startPosition: AbsolutePosition,
    scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    var position = startPosition
    var lineComments: [(start: AbsolutePosition, text: String)] = []
    var lineCommentGroupStart: AbsolutePosition?

    for piece in trivia {
      let pieceStart = position
      let pieceLength = piece.sourceLength.utf8Length
      position = position.advanced(by: pieceLength)

      switch piece {
      case .lineComment(let text):
        if lineCommentGroupStart == nil {
          lineCommentGroupStart = pieceStart
        }
        lineComments.append((pieceStart, text))

      case .blockComment(let text):
        // If cursor is in this block comment, offer to convert to line comments
        let pieceRange = pieceStart..<position
        if pieceRange.overlaps(scope.range) {
          let indentation = leadingIndentation(at: pieceStart, in: scope.snapshot.text)
          return CodeAction(
            title: "Convert Block Comment to Line Comments",
            kind: .refactorInline,
            edit: WorkspaceEdit(changes: [
              scope.snapshot.uri: [
                TextEdit(
                  range: scope.snapshot.absolutePositionRange(of: pieceRange),
                  newText: blockToLineComments(text, indentation: indentation)
                )
              ]
            ])
          )
        }

      case .newlines, .carriageReturns, .carriageReturnLineFeeds:
        // Newline continues a potential line comment group
        continue

      case .spaces, .tabs:
        // Whitespace is allowed between line comments
        continue

      default:
        // Other trivia breaks the line comment group
        if let action = lineCommentsAction(lineComments, groupStart: lineCommentGroupStart, scope: scope) {
          return action
        }
        lineComments.removeAll()
        lineCommentGroupStart = nil
      }
    }

    // Check remaining line comments at end of trivia
    return lineCommentsAction(lineComments, groupStart: lineCommentGroupStart, scope: scope)
  }

  private static func lineCommentsAction(
    _ comments: [(start: AbsolutePosition, text: String)],
    groupStart: AbsolutePosition?,
    scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    guard !comments.isEmpty, let start = groupStart else {
      return nil
    }

    let lastComment = comments.last!
    let end = lastComment.start.advanced(by: lastComment.text.utf8.count)
    let groupRange = start..<end

    guard groupRange.overlaps(scope.range) else {
      return nil
    }

    let indentation = leadingIndentation(at: start, in: scope.snapshot.text)
    let texts = comments.map { String($0.text.dropFirst(2)) }  // Remove "//"

    return CodeAction(
      title: "Convert Line Comments to Block Comment",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [
        scope.snapshot.uri: [
          TextEdit(
            range: scope.snapshot.absolutePositionRange(of: groupRange),
            newText: lineToBlockComment(texts, indentation: indentation)
          )
        ]
      ])
    )
  }

  private static func lineToBlockComment(_ lines: [String], indentation: String) -> String {
    if lines.count == 1 {
      return "/*\(lines[0])*/"
    }
    return "/*\n" + lines.map { "\(indentation)\($0)\n" }.joined() + "\(indentation)*/"
  }

  private static func blockToLineComments(_ text: String, indentation: String) -> String {
    let body = String(text.dropFirst(2).dropLast(2))  // Remove /* and */
    var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    // Trim empty first/last lines from multiline block comments
    if lines.count > 1 {
      if lines.first?.allSatisfy(\.isWhitespace) == true { lines.removeFirst() }
      if lines.last?.allSatisfy(\.isWhitespace) == true { lines.removeLast() }
    }
    if lines.isEmpty { lines = [""] }

    return lines.map { line in
      let trimmed = line.hasPrefix(indentation) ? String(line.dropFirst(indentation.count)) : line
      return "//\(trimmed)"
    }.joined(separator: "\n")
  }

  private static func leadingIndentation(at position: AbsolutePosition, in source: String) -> String {
    let index = source.utf8.index(source.startIndex, offsetBy: position.utf8Offset)
    let lineStart = source[..<index].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
    return String(source[lineStart..<index].prefix { $0 == " " || $0 == "\t" })
  }
}