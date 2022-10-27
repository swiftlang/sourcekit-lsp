import SwiftSyntax
import LanguageServerProtocol
import SwiftRefactor

struct OpaqueParameterToGeneric: CodeActionProvider {
  static var kind: CodeActionKind { .refactorRewrite }

  static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction] {
    guard
      let token = scope.file.token(at: scope.range.offset),
      let decl = token.parent?.as(DeclSyntax.self)
    else {
      return []
    }

    guard let replaced = SwiftRefactor.OpaqueParameterToGeneric.refactor(syntax: decl) else {
      return []
    }
    return [
      ProvidedAction(title: "Expand opaque parameters to generic parameters") {
        Replace(decl, with: replaced)
      }
    ]
  }
}


