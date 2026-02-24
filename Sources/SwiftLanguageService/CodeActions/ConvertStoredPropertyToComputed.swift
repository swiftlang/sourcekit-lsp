import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder

extension ConvertStoredPropertyToComputed: SyntaxCodeActionProvider {

  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard
      let variableDecl = scope.innermostNodeContainingRange?.as(VariableDeclSyntax.self)
        ?? scope.innermostNodeContainingRange?.parent?.as(VariableDeclSyntax.self)
    else {
      return []
    }

    var resolvedType: TypeSyntax? = nil

    if let firstInfo: CursorInfo = scope.cursorInfo.first,
      let annotatedDecl = firstInfo.annotatedDeclaration,
      let typeString = extractType(from: annotatedDecl)
    {
      resolvedType = TypeSyntax(stringLiteral: typeString)
    }

    if resolvedType == nil,
      let explicitType = variableDecl.bindings.first?.typeAnnotation?.type
    {
      resolvedType = explicitType
    }

    let context = ConvertStoredPropertyToComputed.Context(type: resolvedType)

    guard let refactoredDecl = try? Self.refactor(syntax: variableDecl, in: context) else {
      return []
    }

    let edit = TextEdit(
      range: scope.snapshot.absolutePositionRange(of: variableDecl.range),
      newText: refactoredDecl.description
    )

    return [
      CodeAction(
        title: "Convert to computed property",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  private static func extractType(from annotatedDecl: String) -> String? {

    guard let start = annotatedDecl.range(of: "<type>"),
      let end = annotatedDecl.range(of: "</type>")
    else { return nil }
    return String(annotatedDecl[start.upperBound..<end.lowerBound])
  }
}
