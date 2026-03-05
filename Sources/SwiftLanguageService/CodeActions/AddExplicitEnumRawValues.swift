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

/// Syntactic code action provider to add explicit raw values to enum cases
/// when the enum has an implicit raw value type (`Int` or `String`).
///
/// ## Before
///
/// ```swift
/// enum Status: Int {
///     case active
///     case inactive
///     case pending = 10
///     case archived
/// }
/// ```
///
/// ## After
///
/// ```swift
/// enum Status: Int {
///     case active = 0
///     case inactive = 1
///     case pending = 10
///     case archived = 11
/// }
/// ```
struct AddExplicitEnumRawValues: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard
      let node = scope.innermostNodeContainingRange,
      let enumDecl = node.findParentOfSelf(
        ofType: EnumDeclSyntax.self,
        stoppingIf: { $0.is(CodeBlockSyntax.self) }
      )
    else {
      return []
    }

    // Determine the raw value type from the inheritance clause.
    guard let rawValueType = enumDecl.rawValueType else {
      return []
    }

    // Collect all enum case elements.
    let caseElements = enumDecl.memberBlock.members.flatMap { member -> [EnumCaseElementSyntax] in
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return [] }
      return Array(caseDecl.elements)
    }

    // Check that at least one case is missing an explicit raw value.
    let hasMissingRawValue = caseElements.contains { $0.rawValue == nil }
    guard hasMissingRawValue else {
      return []
    }

    // Build the edits.
    var edits: [TextEdit] = []

    switch rawValueType {
    case .int:
      var nextValue = 0
      for element in caseElements {
        if let rawValue = element.rawValue {
          // Parse the existing raw value to determine the next implicit value.
          let rawText = rawValue.value.description.filter { !$0.isWhitespace }
          if let intValue = Int(rawText) {
            nextValue = intValue + 1
          }
        } else {
          // Insert " = <value>" after the element name.
          let insertionText = " = \(nextValue)"
          let position = scope.snapshot.position(
            of: element.name.endPositionBeforeTrailingTrivia
          )
          edits.append(TextEdit(range: position..<position, newText: insertionText))
          nextValue += 1
        }
      }

    case .string:
      for element in caseElements where element.rawValue == nil {
        let insertionText = " = \"\(element.name.text)\""
        let position = scope.snapshot.position(
          of: element.name.endPositionBeforeTrailingTrivia
        )
        edits.append(TextEdit(range: position..<position, newText: insertionText))
      }
    }

    guard !edits.isEmpty else {
      return []
    }

    return [
      CodeAction(
        title: "Add explicit raw values",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: edits])
      )
    ]
  }
}

// MARK: - Helpers

private enum RawValueKind {
  case int
  case string
}

private extension EnumDeclSyntax {
  /// Determine the raw value type if it's `Int` or `String`.
  var rawValueType: RawValueKind? {
    guard let inheritanceClause = self.inheritanceClause else {
      return nil
    }
    for inheritance in inheritanceClause.inheritedTypes {
      let typeName = inheritance.type.trimmedDescription
      switch typeName {
      case "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
        return .int
      case "String":
        return .string
      default:
        continue
      }
    }
    return nil
  }
}
