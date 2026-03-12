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
import SwiftSyntax

/// Syntactic code action provider to convert line comments and block comments
/// preceding a declaration into doc comments.
struct ConvertCommentToDocComment: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    let cursorPosition = scope.snapshot.absolutePosition(of: scope.request.range.lowerBound)

    guard let token = scope.file.token(at: cursorPosition) else {
      return []
    }

    guard Self.cursorIsInsideConvertibleComment(token: token, cursorPosition: cursorPosition) else {
      return []
    }

    guard
      let declaration = Syntax(token).findParentOfSelf(
        ofType: DeclSyntax.self,
        stoppingIf: { $0.kind == .codeBlockItem || $0.kind == .memberBlockItem }
      )
    else {
      return []
    }

    guard let firstToken = declaration.firstToken(viewMode: .sourceAccurate),
      firstToken.id == token.id
    else {
      return []
    }

    let newTrivia = Trivia(
      pieces: firstToken.leadingTrivia.map { piece in
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

    let newDecl = declaration.with(\.leadingTrivia, newTrivia)
    let edit = TextEdit(
      range: scope.snapshot.range(of: declaration),
      newText: newDecl.description
    )

    return [
      CodeAction(
        title: "Convert Comment to Doc Comment",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  private static func cursorIsInsideConvertibleComment(
    token: TokenSyntax,
    cursorPosition: AbsolutePosition
  )
    -> Bool
  {
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
