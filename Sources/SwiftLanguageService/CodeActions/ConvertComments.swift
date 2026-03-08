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
import SwiftBasicFormat
import SwiftExtensions
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
      token: token,
      scope: scope
    ) {
      return [action]
    }

    return []
  }

  private static func codeAction(
    for trivia: Trivia,
    startPosition: AbsolutePosition,
    token: TokenSyntax,
    scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    var position = startPosition
    var lineComments: [(start: AbsolutePosition, text: String)] = []
    var consecutiveNewlines = 0

    for piece in trivia {
      let pieceStart = position
      let pieceLength = piece.sourceLength.utf8Length
      position = position.advanced(by: pieceLength)

      switch piece {
      case .lineComment(let text):
        lineComments.append((pieceStart, text))
        consecutiveNewlines = 0

      case .blockComment(let text):
        // If cursor is in this block comment, offer to convert to line comments
        let pieceRange = pieceStart..<position
        if pieceRange.overlaps(scope.range) {
          let indentation = token.indentationOfLine.description
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
        consecutiveNewlines = 0

      case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count):
        consecutiveNewlines += count
        // Break line comment group if there's an empty line (2+ newlines)
        if consecutiveNewlines >= 2 && !lineComments.isEmpty {
          if let action = lineCommentsAction(lineComments, token: token, scope: scope) {
            return action
          }
          lineComments.removeAll()
        }

      case .spaces, .tabs:
        // Whitespace is allowed between line comments
        continue

      default:
        // Other trivia breaks the line comment group
        if let action = lineCommentsAction(lineComments, token: token, scope: scope) {
          return action
        }
        lineComments.removeAll()
        consecutiveNewlines = 0
      }
    }

    // Check remaining line comments at end of trivia
    return lineCommentsAction(lineComments, token: token, scope: scope)
  }

  private static func lineCommentsAction(
    _ comments: [(start: AbsolutePosition, text: String)],
    token: TokenSyntax,
    scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    guard let firstComment = comments.first, let lastComment = comments.last else {
      return nil
    }

    let start = firstComment.start
    let end = lastComment.start.advanced(by: lastComment.text.utf8.count)
    let groupRange = start..<end

    guard groupRange.overlaps(scope.range) else {
      return nil
    }

    let indentation = token.indentationOfLine.description
    let texts = comments.map { String($0.text.dropFirst(2)) }  // Remove "//"
    let title = comments.count == 1 ? "Convert Line Comment to Block Comment" : "Convert Line Comments to Block Comment"

    return CodeAction(
      title: title,
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
    if let line = lines.only {
      return "/*\(line)*/"
    }
    return """
      /*
      \(lines.map { "\(indentation)\($0)" }.joined(separator: "\n"))
      \(indentation)*/
      """
  }

  private static func blockToLineComments(_ text: String, indentation: String) -> String {
    let body = String(text.dropFirst(2).dropLast(2))  // Remove /* and */
    var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    // Trim empty first/last lines from multiline block comments
    if lines.first?.allSatisfy(\.isWhitespace) ?? false { lines.removeFirst() }
    if lines.last?.allSatisfy(\.isWhitespace) ?? false { lines.removeLast() }
    if lines.isEmpty { lines = [""] }

    return lines.map { line in
      let trimmed = line.hasPrefix(indentation) ? String(line.dropFirst(indentation.count)) : line
      return "//\(trimmed)"
    }.joined(separator: "\n")
  }
}
