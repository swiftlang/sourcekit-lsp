//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SwiftRefactor
import SwiftSyntax

/// Protocol that adapts a SyntaxRefactoringProvider (that comes from
/// swift-syntax) into a SyntaxCodeActionProvider.
protocol SyntaxRefactoringCodeActionProvider: SyntaxCodeActionProvider, SyntaxRefactoringProvider {
  static var title: String { get }
}

/// SyntaxCodeActionProviders with a \c Void context can automatically be
/// adapted provide a code action based on their refactoring operation.
extension SyntaxRefactoringCodeActionProvider where Self.Context == Void {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard
      let token = scope.firstToken,
      let node = token.parent?.as(Input.self)
    else {
      return []
    }

    guard let refactored = Self.refactor(syntax: node) else {
      return []
    }

    let edit = TextEdit(
      range: scope.snapshot.range(of: node),
      newText: refactored.description
    )

    return [
      CodeAction(
        title: Self.title,
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }
}

// Adapters for specific refactoring provides in swift-syntax.

extension AddSeparatorsToIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Add digit separators" }
}

extension FormatRawStringLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String {
    "Convert string literal to minimal number of '#'s"
  }
}

extension MigrateToNewIfLetSyntax: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Migrate to shorthand 'if let' syntax" }
}

extension OpaqueParameterToGeneric: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Expand 'some' parameters to generic parameters" }
}

extension RemoveSeparatorsFromIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Remove digit separators" }
}
