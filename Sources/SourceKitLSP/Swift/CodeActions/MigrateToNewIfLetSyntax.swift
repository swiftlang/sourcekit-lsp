import SwiftSyntax
import LanguageServerProtocol
import SwiftRefactor

struct MigrateToNewIfLetSyntax: CodeActionProvider {
  static var kind: CodeActionKind { .refactorRewrite }

  static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction] {
    guard
      let token = scope.file.token(at: scope.range.offset),
      let binding = token.parent?.as(IfExprSyntax.self)
    else {
      return []
    }

    guard let refactoredCondition = SwiftRefactor.MigrateToNewIfLetSyntax.refactor(syntax: binding) else {
      return []
    }
    return [
      ProvidedAction(title: "Migrate to 'if-let' Syntax") {
        Replace(binding, with: refactoredCondition)
      }
    ]
  }
}
