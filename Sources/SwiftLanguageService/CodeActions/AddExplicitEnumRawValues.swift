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

import SwiftRefactor
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
struct AddExplicitEnumRawValues: EditRefactoringProvider {
  static func textRefactor(syntax: EnumDeclSyntax, in context: Void) throws -> [SourceEdit] {
    // Determine the raw value type from the first type in the inheritance clause.
    guard let rawValueType = syntax.rawValueType else {
      throw RefactoringNotApplicableError("enum does not have an Int or String raw value type")
    }

    // Collect all enum case elements.
    let caseElements = syntax.memberBlock.members.flatMap { member -> [EnumCaseElementSyntax] in
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return [] }
      return Array(caseDecl.elements)
    }

    // Check that at least one case is missing an explicit raw value.
    guard caseElements.contains(where: { $0.rawValue == nil }) else {
      throw RefactoringNotApplicableError("all cases already have explicit raw values")
    }

    // Build the edits.
    var edits: [SourceEdit] = []

    switch rawValueType {
    case .int:
      var nextValue = 0
      for element in caseElements {
        if let rawValue = element.rawValue {
          // Only handle integer literal raw values. If we encounter something
          // we don't understand, bail out rather than risk generating incorrect code.
          guard let intLiteral = rawValue.value.as(IntegerLiteralExprSyntax.self),
            let intValue = Int(intLiteral.literal.text)
          else {
            throw RefactoringNotApplicableError("unsupported raw value expression")
          }
          nextValue = intValue + 1
        } else {
          let insertionText = " = \(nextValue)"
          let position = element.name.endPositionBeforeTrailingTrivia
          edits.append(SourceEdit(range: position..<position, replacement: insertionText))
          nextValue += 1
        }
      }

    case .string:
      for element in caseElements where element.rawValue == nil {
        let insertionText = " = \"\(element.name.text)\""
        let position = element.name.endPositionBeforeTrailingTrivia
        edits.append(SourceEdit(range: position..<position, replacement: insertionText))
      }
    }

    if edits.isEmpty {
      throw RefactoringNotApplicableError("no cases to transform")
    }

    return edits
  }
}

extension AddExplicitEnumRawValues: SyntaxRefactoringCodeActionProvider {
  static let title: String = "Add explicit raw values"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> EnumDeclSyntax? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: EnumDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) }
    )
  }
}

// MARK: - Helpers

private enum RawValueKind {
  case int
  case string
}

private extension EnumDeclSyntax {
  /// Determine the raw value type if the first inherited type is `Int` or `String`.
  /// Only the first type in the inheritance clause may specify a raw value.
  var rawValueType: RawValueKind? {
    guard let firstType = inheritanceClause?.inheritedTypes.first else {
      return nil
    }
    let typeName = firstType.type.trimmedDescription
    switch typeName {
    case "Int", "Int8", "Int16", "Int32", "Int64", "Int128",
      "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128":
      return .int
    case "String":
      return .string
    default:
      return nil
    }
  }
}
