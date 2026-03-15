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

extension CodeActionKind {
  static let refactorMove = CodeActionKind(rawValue: "refactor.move")
}

struct MoveMember: SyntaxCodeActionProvider {

  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {

    guard
      let member =
        scope.innermostNodeContainingRange?
        .findParentOfSelf(
          ofType: MemberBlockItemSyntax.self,
          stoppingIf: { $0.is(SourceFileSyntax.self) }
        )
    else {
      return []
    }

    return [
      CodeAction(
        title: "Move to another type",
        kind: .refactorMove,
        command: Command(
          title: "Move to another type",
          command: "swift.moveMember",
          arguments: [
            .string(scope.snapshot.uri.stringValue),
            .int(member.position.utf8Offset),
            .int(member.endPosition.utf8Offset),
          ]
        )
      )
    ]
  }
}
