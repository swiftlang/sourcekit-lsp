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
internal import SourceKitLSP
import SwiftRefactor
import SwiftSyntax

/// Syntactic code action provider to convert line comments and block comments
/// preceding a declaration into doc comments.
struct ConvertCommentToDocComment: SyntaxRefactoringProvider {
  static func refactor(syntax: DeclSyntax, in context: Void) throws -> DeclSyntax {
    let newTrivia = Trivia(
      pieces: syntax.leadingTrivia.map { piece in
        switch piece {
        case let .lineComment(text):
          return .docLineComment("/" + text)
        case let .blockComment(text):
          return .docBlockComment("/**" + text.dropFirst(2))
        default:
          return piece
        }
      }
    )
    return syntax.with(\.leadingTrivia, newTrivia)
  }
}

extension ConvertCommentToDocComment: SyntaxRefactoringCodeActionProvider {
  static let title = "Convert Comment to Doc Comment"

  static func nodeToRefactor(in scope: CodeActionScope) -> DeclSyntax? {
    let cursorPosition = scope.snapshot.absolutePosition(of: scope.request.range.lowerBound)
    guard let token = scope.file.token(at: cursorPosition) else {
      return nil
    }
    guard cursorIsInsideConvertibleComment(token: token, cursorPosition: cursorPosition) else {
      return nil
    }
    guard
      let declaration = Syntax(token).findParentOfSelf(
        ofType: DeclSyntax.self,
        stoppingIf: { $0.kind == .codeBlockItem || $0.kind == .memberBlockItem }
      )
    else { return nil }

    guard let firstToken = declaration.firstToken(viewMode: .sourceAccurate),
      firstToken.id == token.id
    else { return nil }

    return declaration
  }

  private static func cursorIsInsideConvertibleComment(
    token: TokenSyntax,
    cursorPosition: AbsolutePosition
  ) -> Bool {
    var offset = token.position
    for piece in token.leadingTrivia {
      let pieceStart = offset
      let pieceEnd = offset + piece.sourceLength
      switch piece {
      case .blockComment,
        .lineComment:
        if pieceStart <= cursorPosition && cursorPosition < pieceEnd {
          return true
        }

      default:
        break
      }
      offset = pieceEnd
    }
    return false
  }
}
