import SwiftSyntax
import LanguageServerProtocol
import SwiftRefactor

struct ReformatIntegerLiteral: CodeActionProvider {
  static var kind: CodeActionKind { .refactorRewrite }

  static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction] {
    guard
      let token = scope.file.token(at: scope.range.offset),
      let literal = token.parent?.as(IntegerLiteralExprSyntax.self),
      literal.literal.text.count > 4
    else {
      return []
    }

    var actions: [ProvidedAction] = []
    if let removedLiteral = RemoveSeparatorsFromIntegerLiteral.refactor(syntax: literal) {
      actions.append(
        ProvidedAction(title: "Remove digit separators") {
          Replace(literal, with: removedLiteral)
        }
      )
    } 

    if let addedLiteral = AddSeparatorsToIntegerLiteral.refactor(syntax: literal) {
      actions.append(
        ProvidedAction(title: "Add digit separators") {
          Replace(literal, with: addedLiteral)
        }
      )
    }

    return actions
  }
}
