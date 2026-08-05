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

/// Syntactic code action provider that adds explicit raw values to all cases of
/// an enum whose first inherited type is `Int`/`UInt` (any width) or `String`.
///
/// For an enum with an integer raw value type, the action computes raw values
/// following Swift's implicit numbering rules: counting starts at zero and
/// continues from the last explicit value. For a `String` raw value type, each
/// case without an explicit value is given a raw value equal to the case name.
///
/// ### Example
///
/// Before:
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
/// After:
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
    guard let rawValueType = syntax.rawValueType else {
      throw RefactoringNotApplicableError("Enum does not have an Int, UInt, or String raw value type")
    }

    // Attached macros applied to the enum can introduce new cases via
    // attribute-level macro expansion, which is not visible to a syntactic
    // walk. Bail conservatively whenever there are any attributes; a follow-up
    // can narrow this once we have a reliable way to tell apart attribute
    // macros from non-macro attributes such as `@available`.
    if !syntax.attributes.isEmpty {
      throw RefactoringNotApplicableError("Enum has attributes that may be attached macros")
    }

    // `#if` blocks and freestanding macro expansions can introduce or hide
    // enum cases without that being visible to a purely syntactic walk. In
    // either case the implicit raw value counter cannot be computed safely,
    // so bail rather than risk emitting values that disagree with the active
    // configuration or expanded source.
    for member in syntax.memberBlock.members {
      if member.decl.is(IfConfigDeclSyntax.self) {
        throw RefactoringNotApplicableError("Enum contains #if directives")
      }
      if member.decl.is(MacroExpansionDeclSyntax.self) {
        throw RefactoringNotApplicableError("Enum contains a freestanding macro expansion")
      }
    }

    let caseElements = syntax.memberBlock.members.flatMap { member -> [EnumCaseElementSyntax] in
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return [] }
      return Array(caseDecl.elements)
    }

    // Cases with associated values cannot have raw values; mixing them inside a
    // raw-value enum is invalid Swift, but a user might be editing toward that
    // state. Don't attempt the refactor in that case.
    if caseElements.contains(where: { $0.parameterClause != nil }) {
      throw RefactoringNotApplicableError("Enum has cases with associated values")
    }

    guard caseElements.contains(where: { $0.rawValue == nil }) else {
      throw RefactoringNotApplicableError("All cases already have explicit raw values")
    }

    var edits: [SourceEdit] = []

    switch rawValueType {
    case .signedInt, .unsignedInt:
      let allowNegative = rawValueType == .signedInt
      var nextValue = 0
      for element in caseElements {
        if let rawValue = element.rawValue {
          // Only proceed when the existing raw value is a recognised integer
          // literal (optionally with a leading minus). Anything else, such as a
          // reference to a constant or an arithmetic expression, is rejected so
          // the refactoring never emits values that disagree with the source.
          guard let intValue = rawValue.value.signedIntegerLiteralValue else {
            throw RefactoringNotApplicableError("Unsupported raw value expression")
          }
          if !allowNegative, intValue < 0 {
            throw RefactoringNotApplicableError("Negative raw value on an unsigned-integer enum")
          }
          let (next, overflow) = intValue.addingReportingOverflow(1)
          if overflow {
            throw RefactoringNotApplicableError("Raw value continuation would overflow Int")
          }
          nextValue = next
        } else {
          let insertion = " = \(nextValue)"
          let position = element.name.endPositionBeforeTrailingTrivia
          edits.append(SourceEdit(range: position..<position, replacement: insertion))
          let (next, overflow) = nextValue.addingReportingOverflow(1)
          if overflow {
            throw RefactoringNotApplicableError("Raw value continuation would overflow Int")
          }
          nextValue = next
        }
      }

    case .string:
      for element in caseElements where element.rawValue == nil {
        // Swift's implicit string raw value uses the canonical identifier name
        // without any surrounding backticks (e.g. `` case `default` `` has the
        // implicit raw value `"default"`, not `` "`default`" ``).
        let name = element.name.identifier?.name ?? element.name.text
        let insertion = " = \"\(name)\""
        let position = element.name.endPositionBeforeTrailingTrivia
        edits.append(SourceEdit(range: position..<position, replacement: insertion))
      }
    }

    if edits.isEmpty {
      throw RefactoringNotApplicableError("No cases to transform")
    }

    return edits
  }
}

extension AddExplicitEnumRawValues: SyntaxRefactoringCodeActionProvider {
  static let title: String = "Add Explicit Raw Values"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> EnumDeclSyntax? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: EnumDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) }
    )
  }
}

private enum RawValueKind {
  case signedInt
  case unsignedInt
  case string
}

private extension EnumDeclSyntax {
  /// The raw value kind if the first inherited type is a supported integer
  /// type or `String`. Only the first type in the inheritance clause may
  /// specify a raw value, so all other inherited types are protocols.
  var rawValueType: RawValueKind? {
    guard let firstType = inheritanceClause?.inheritedTypes.first else {
      return nil
    }
    switch firstType.type.trimmedDescription {
    case "Int", "Int8", "Int16", "Int32", "Int64", "Int128":
      return .signedInt
    case "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128":
      return .unsignedInt
    case "String":
      return .string
    default:
      return nil
    }
  }
}

private extension ExprSyntax {
  /// Parse this expression as a signed integer literal. Uses swift-syntax's
  /// `IntegerLiteralExprSyntax.representedLiteralValue` for plain integer
  /// literals (all bases and underscore separators), and unwraps a unary minus
  /// prefix expression for negative literals. Returns `nil` for anything else.
  var signedIntegerLiteralValue: Int? {
    if let intLit = self.as(IntegerLiteralExprSyntax.self) {
      return intLit.representedLiteralValue
    }
    if let prefix = self.as(PrefixOperatorExprSyntax.self),
      prefix.operator.text == "-",
      let intLit = prefix.expression.as(IntegerLiteralExprSyntax.self),
      let positive = intLit.representedLiteralValue
    {
      return -positive
    }
    return nil
  }
}
