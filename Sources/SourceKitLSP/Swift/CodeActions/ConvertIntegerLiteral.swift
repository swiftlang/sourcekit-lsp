import SwiftSyntax
import LanguageServerProtocol
import SwiftRefactor

// TODO: Make the type IntegerLiteralExprSyntax.Radix conform to CaseEnumerable
// in swift-syntax.

extension IntegerLiteralExprSyntax.Radix {
  static var allCases: [Self] = [.binary, .octal, .decimal, .hex]
}

public struct ConvertIntegerLiteral: CodeActionProvider {
  public static var kind: CodeActionKind { .refactorInline }

  public static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction] {
    guard
      let token = scope.file.token(at: scope.range.offset),
      let lit = token.parent?.as(IntegerLiteralExprSyntax.self),
      let integerValue = Int(lit.split().value, radix: lit.radix.size)
    else {
      return []
    }

    var actions = [ProvidedAction]()
    let currentRadix = lit.radix
    for radix in IntegerLiteralExprSyntax.Radix.allCases {
      guard radix != currentRadix else {
        continue
      }

      //TODO: Add this to swift-syntax?
      let prefix: String
      switch radix {
      case .binary:
        prefix = "0b"
      case .octal:
        prefix = "0o"
      case .hex:
        prefix = "0x"
      case .decimal:
        prefix = ""
      }

      let convertedValue: ExprSyntax =
        "\(raw: prefix)\(raw: String(integerValue, radix: radix.size))"
      actions.append(ProvidedAction(title: "Convert \(lit) to \(convertedValue)") {
        Replace(lit, with: convertedValue)
      })
    }

    return actions
  }
}
