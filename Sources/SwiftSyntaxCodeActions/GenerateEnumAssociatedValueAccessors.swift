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

@_spi(SourceKitLSP) package import LanguageServerProtocol
package import SourceKitLSP
import SwiftExtensions
package import SwiftSyntax
/// Syntactic code action to generate computed property accessors for an enum case's associated values.
///
/// When the cursor is on an enum case that has associated values, this action generates:
/// - A `var as<Case>: Type?` computed property that extracts the associated value.
/// - A `var is<Case>: Bool` computed property that checks for the case.
///
/// ## Before
///
/// ```swift
/// enum Value {
///     case text(String)
/// }
/// ```
///
/// ## After
///
/// ```swift
/// enum Value {
///     case text(String)
///
///     var asText: String? {
///         if case let .text(v) = self { return v }
///         return nil
///     }
///
///     var isText: Bool {
///         if case .text = self { return true }
///         return false
///     }
/// }
/// ```
package struct GenerateEnumAssociatedValueAccessors: SyntaxCodeActionProvider {
    package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
          // Find the enum case declaration containing the cursor.
          guard let enumCase = scope.innermostNodeContainingRange?.findParentOfSelf(
                  ofType: EnumCaseDeclSyntax.self,
                  stoppingIf: { $0.is(SourceFileSyntax.self) || $0.is(CodeBlockSyntax.self) }
          ) else { return [] }

          // Find the enclosing enum declaration so we can insert into its member block.
          guard let enumDecl = enumCase.findParentOfSelf(
                  ofType: EnumDeclSyntax.self,
                  stoppingIf: { $0.is(SourceFileSyntax.self) }
          ) else { return [] }

          // Only act on elements that actually have associated values.
          let elements = enumCase.elements.filter {
                  $0.parameterClause?.parameters.isEmpty == false
          }
          guard !elements.isEmpty else { return [] }

          // Use the indentation of the case keyword as the property indentation.
          let indent = enumCase.firstToken(viewMode: .sourceAccurate)?.indentationOfLine.description ?? "    "
          let bodyIndent = indent + "    "

          var insertText = ""
          for element in elements {
                  guard let params = element.parameterClause?.parameters, !params.isEmpty else { continue }

                  let caseName = element.name.text
                  let capitalizedName = caseName.prefix(1).uppercased() + caseName.dropFirst()
                  let types = params.map { $0.type.description.trimmingCharacters(in: .whitespaces) }

                  let returnType: String
                  let patternVars: String
                  let returnExpr: String

                  if params.count == 1 {
                            returnType = types[0]
                            patternVars = "v"
                            returnExpr = "v"
                  } else {
                            returnType = "(" + types.joined(separator: ", ") + ")"
                            let varNames = (0..<params.count).map { "v\($0)" }
                            patternVars = varNames.joined(separator: ", ")
                            returnExpr = "(" + varNames.joined(separator: ", ") + ")"
                  }

                  // var as<Case>: Type? { ... }
                  insertText += "\n"
                  insertText += "\(indent)var as\(capitalizedName): \(returnType)? {\n"
                  insertText += "\(bodyIndent)if case let .\(caseName)(\(patternVars)) = self { return \(returnExpr) }\n"
                  insertText += "\(bodyIndent)return nil\n"
                  insertText += "\(indent)}\n"

                  // var is<Case>: Bool { ... }
                  insertText += "\n"
                  insertText += "\(indent)var is\(capitalizedName): Bool {\n"
                  insertText += "\(bodyIndent)if case .\(caseName) = self { return true }\n"
                  insertText += "\(bodyIndent)return false\n"
                  insertText += "\(indent)}\n"
          }

          // Insert the new members before the enum's closing brace.
          let insertPos = enumDecl.memberBlock.rightBrace.position
          let edit = TextEdit(
                  range: scope.snapshot.positionRange(of: insertPos..<insertPos),
                  newText: insertText
          )

          return [
                  CodeAction(
                            title: "Generate enum associated value accessors",
                            kind: .refactorInline,
                            edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
                  )
          ]
    }
}
