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

/// A code action that generates computed properties to extract associated
/// values and check cases for an enum.
///
/// For each case with associated values, generates:
/// - `asX: T?` — extracts the associated value, or `nil` if a different case
/// - `isX: Bool` — returns `true` if the value matches that case
///
/// Example:
/// ```swift
/// enum Value {
///     case text(String)
///     case number(Int)
/// }
/// ```
/// Generates `asText`, `isText`, `asNumber`, `isNumber` computed properties.
struct GenerateEnumAssociatedValueAccessors: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    guard let enumDecl = node.findParentOfSelf(
      ofType: EnumDeclSyntax.self,
      stoppingIf: { _ in false }
    ) else {
      return []
    }

    // Collect all cases with associated values.
    let casesWithAssociatedValues = enumDecl.memberBlock.members.compactMap { member -> EnumCaseElementSyntax? in
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
            let element = caseDecl.elements.first,
            caseDecl.elements.count == 1,
            element.parameterClause != nil
      else {
        return nil
      }
      return element
    }

    if casesWithAssociatedValues.isEmpty {
      return []
    }

    // Scan existing member names to avoid duplicates.
    let existingMembers = Set(
      enumDecl.memberBlock.members.compactMap { member -> String? in
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
          return nil
        }
        return pattern.identifier.text
      }
    )

    var accessors: [String] = []

    for element in casesWithAssociatedValues {
      let caseName = element.name.text
      let capitalizedName = caseName.prefix(1).uppercased() + caseName.dropFirst()
      let asName = "as\(capitalizedName)"
      let isName = "is\(capitalizedName)"

      guard let paramClause = element.parameterClause else { continue }
      let params = Array(paramClause.parameters)

      if params.count == 1 {
        let typeText = params[0].type.trimmedDescription

        if !existingMembers.contains(asName) {
          accessors.append(
            """
                var \(asName): \(typeText)? {
                    if case let .\(caseName)(v) = self { return v }
                    return nil
                }
            """
          )
        }
      } else {
        let tupleTypes = params.map { $0.type.trimmedDescription }
        let returnType = "(\(tupleTypes.joined(separator: ", ")))"
        let bindingVars = (0..<params.count).map { "v\($0)" }
        let bindingPattern = bindingVars.joined(separator: ", ")

        if !existingMembers.contains(asName) {
          accessors.append(
            """
                var \(asName): \(returnType)? {
                    if case let .\(caseName)(\(bindingPattern)) = self { return (\(bindingPattern)) }
                    return nil
                }
            """
          )
        }
      }

      if !existingMembers.contains(isName) {
        accessors.append(
          """
              var \(isName): Bool {
                  if case .\(caseName) = self { return true }
                  return false
              }
          """
        )
      }
    }

    if accessors.isEmpty {
      return []
    }

    // Insert before the closing brace.
    let closingBrace = enumDecl.memberBlock.rightBrace
    let insertPosition = scope.snapshot.position(of: closingBrace.positionAfterSkippingLeadingTrivia)

    let insertionText = "\n" + accessors.joined(separator: "\n\n") + "\n"

    return [
      CodeAction(
        title: "Generate enum associated value accessors",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: Range(
                  uncheckedBounds: (lower: insertPosition, upper: insertPosition)
                ),
                newText: insertionText
              )
            ]
          ]
        )
      )
    ]
  }
}
