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

/// Syntactic code action provider to convert regular comments into
/// documentation comments.
///
/// ## Before
///
/// ```swift
/// // Returns the full name of the user
/// // by combining first and last name.
/// func fullName() -> String {
/// ```
///
/// ## After
///
/// ```swift
/// /// Returns the full name of the user
/// /// by combining first and last name.
/// func fullName() -> String {
/// ```
struct ConvertCommentToDocComment: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    // Find a declaration node containing the cursor.
    guard
      let node = scope.innermostNodeContainingRange,
      let decl = node.findParentOfSelf(
        ofType: DeclSyntax.self,
        stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) || $0.is(ExprSyntax.self) }
      )
    else {
      return []
    }

    let trivia = decl.leadingTrivia

    // Check that there's at least one regular comment but no existing doc comment.
    var hasLineComment = false
    var hasBlockComment = false
    for piece in trivia {
      switch piece {
      case .lineComment:
        hasLineComment = true
      case .blockComment:
        hasBlockComment = true
      case .docLineComment, .docBlockComment:
        // Already has documentation — don't offer the action.
        return []
      default:
        break
      }
    }

    guard hasLineComment || hasBlockComment else {
      return []
    }

    // Build new trivia by converting the *last contiguous block* of line
    // comments (or the last block comment) immediately before the declaration
    // into doc comments. Earlier comments (e.g. section separators) are left
    // untouched.

    let pieces = Array(trivia)
    var converted = pieces

    if hasLineComment {
      // Walk backwards to find the contiguous run of line comments closest
      // to the declaration token.
      var end = pieces.count - 1
      // Skip trailing whitespace/newlines to get to comments.
      while end >= 0 {
        switch pieces[end] {
        case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds:
          end -= 1
        default:
          break
        }
        // Swift doesn't have labeled while-switch, so break out manually.
        if end < 0 { break }
        switch pieces[end] {
        case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds:
          continue
        default:
          break
        }
        break
      }

      // `end` should now point at the last line comment.
      guard end >= 0, case .lineComment = pieces[end] else {
        // Unexpected — the block comment case is handled separately below.
        if hasBlockComment {
          return convertBlockComment(pieces: pieces, scope: scope, decl: decl)
        }
        return []
      }

      // Walk backwards through contiguous line comments (with only
      // whitespace/newline separators between them).
      var start = end
      var i = end - 1
      while i >= 0 {
        switch pieces[i] {
        case .lineComment:
          start = i
          i -= 1
        case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds:
          i -= 1
        default:
          i = -1  // stop
        }
      }

      // Convert each line comment in the range to a doc line comment.
      for idx in start...end {
        if case .lineComment(let text) = pieces[idx] {
          // "// foo" -> "/// foo", "//foo" -> "///foo"
          let docText: String
          if text.hasPrefix("// ") {
            docText = "///" + text.dropFirst(2)
          } else if text.hasPrefix("//") {
            docText = "/// " + text.dropFirst(2)
          } else {
            docText = "/// " + text
          }
          converted[idx] = .docLineComment(docText)
        }
      }
    } else {
      return convertBlockComment(pieces: pieces, scope: scope, decl: decl)
    }

    let newTrivia = Trivia(pieces: converted)
    let newDecl = decl.with(\.leadingTrivia, newTrivia)

    let range = scope.snapshot.range(of: decl)
    let edit = TextEdit(range: range, newText: newDecl.description)

    return [
      CodeAction(
        title: "Convert to documentation comment",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  /// Convert the last block comment in the trivia into a doc block comment.
  private static func convertBlockComment(
    pieces: [TriviaPiece],
    scope: SyntaxCodeActionScope,
    decl: DeclSyntax
  ) -> [CodeAction] {
    var converted = pieces
    // Find the last block comment.
    guard let idx = pieces.lastIndex(where: {
      if case .blockComment = $0 { return true }
      return false
    }) else {
      return []
    }

    if case .blockComment(let text) = pieces[idx] {
      // "/* foo */" -> "/** foo */"
      let docText: String
      if text.hasPrefix("/*") {
        docText = "/**" + text.dropFirst(2)
      } else {
        docText = "/** " + text + " */"
      }
      converted[idx] = .docBlockComment(docText)
    }

    let newTrivia = Trivia(pieces: converted)
    let newDecl = decl.with(\.leadingTrivia, newTrivia)

    let range = scope.snapshot.range(of: decl)
    let edit = TextEdit(range: range, newText: newDecl.description)

    return [
      CodeAction(
        title: "Convert to documentation comment",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }
}
