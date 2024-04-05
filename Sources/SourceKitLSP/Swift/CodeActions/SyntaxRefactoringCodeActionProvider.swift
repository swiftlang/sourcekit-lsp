import LanguageServerProtocol
import SwiftRefactor
import SwiftSyntax

/// Protocol that adapts a SyntaxRefactoringProvider (that comes from swift-syntax)
/// into a CodeActionProvider.
public protocol SyntaxRefactoringCodeActionProvider: CodeActionProvider, SyntaxRefactoringProvider {
  static var title: String { get }
}

extension SyntaxRefactoringCodeActionProvider where Self.Context == Void {
  public static var kind: CodeActionKind { .refactorRewrite }

  public static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction] {
    guard
      let token = scope.file.token(at: scope.range.offset),
      let binding = token.parent?.as(Input.self)
    else {
      return []
    }

    guard let refactored = Self.refactor(syntax: binding) else {
      return []
    }

    return [
      ProvidedAction(title: Self.title) {
        Replace(binding, with: refactored)
      }
    ]
  }
}

// Adapters for specific refactoring provides in swift-syntax.

extension AddSeparatorsToIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Add digit separators" }
}

extension FormatRawStringLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Format raw string literal" }
}

extension MigrateToNewIfLetSyntax: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Migrate to 'if-let' Syntax" }
}

extension OpaqueParameterToGeneric: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Expand opaque parameters to generic parameters" }
}

extension RemoveSeparatorsFromIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Remove digit separators" }
}
