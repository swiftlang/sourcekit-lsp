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

import SwiftBasicFormat
import SwiftExtensions
import SwiftRefactor
import SwiftSyntax

/// Syntactic code action that adds an `as<Case>` computed property for every
/// enum case with associated values, returning the value(s) as an optional.
struct GenerateEnumCaseAsAccessors: SyntaxRefactoringCodeActionProvider {
  static let title: String = "Generate 'as' accessors for enum cases"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> EnumDeclSyntax? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: EnumDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) }
    )
  }

  static func textRefactor(syntax: EnumDeclSyntax, in context: Void) throws -> [SourceEdit] {
    let indentation = accessorIndentation(for: syntax)

    var accessors: [String] = []
    for element in enumCaseElements(of: syntax) {
      guard let parameters = element.parameterClause?.parameters, !parameters.isEmpty else {
        continue
      }
      accessors.append(
        makeAsAccessor(
          name: "as\(capitalizedCaseName(of: element))",
          casePattern: element.name.text,
          parameters: parameters,
          baseIndentation: indentation.base,
          indentationStep: indentation.step
        )
      )
    }

    return try sourceEdits(insertingAccessors: accessors, into: syntax)
  }

  private static func makeAsAccessor(
    name: String,
    casePattern: String,
    parameters: EnumCaseParameterListSyntax,
    baseIndentation: Trivia,
    indentationStep: Trivia
  ) -> String {
    let memberIndentation = (baseIndentation + indentationStep).description
    let bodyIndentation = (baseIndentation + indentationStep + indentationStep).description
    let bindings = parameters.enumerated().map { index, parameter -> String in
      if let label = parameter.firstName, label.text != "_" {
        return label.text
      }
      return parameters.count == 1 ? "value" : "value\(index + 1)"
    }
    let returnType: String
    if let parameter = parameters.only {
      let type = parameter.type.trimmedDescription
      returnType = needsParenthesesBeforeOptional(parameter.type) ? "(\(type))?" : "\(type)?"
    } else {
      let elements = parameters.map { parameter -> String in
        if let label = parameter.firstName, label.text != "_" {
          return "\(label.text): \(parameter.type.trimmedDescription)"
        }
        return parameter.type.trimmedDescription
      }
      returnType = "(\(elements.joined(separator: ", ")))?"
    }
    let boundValues = bindings.joined(separator: ", ")
    let returnValue = bindings.only ?? "(\(boundValues))"
    return """
      \(memberIndentation)var \(name): \(returnType) {
      \(bodyIndentation)if case let .\(casePattern)(\(boundValues)) = self { return \(returnValue) }
      \(bodyIndentation)return nil
      \(memberIndentation)}
      """
  }
}

/// Syntactic code action that adds an `is<Case>` Boolean computed property for
/// every enum case.
struct GenerateEnumCaseIsAccessors: SyntaxRefactoringCodeActionProvider {
  static let title: String = "Generate 'is' accessors for enum cases"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> EnumDeclSyntax? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: EnumDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) }
    )
  }

  static func textRefactor(syntax: EnumDeclSyntax, in context: Void) throws -> [SourceEdit] {
    let indentation = accessorIndentation(for: syntax)

    let accessors = enumCaseElements(of: syntax).map { element in
      makeIsAccessor(
        name: "is\(capitalizedCaseName(of: element))",
        casePattern: element.name.text,
        baseIndentation: indentation.base,
        indentationStep: indentation.step
      )
    }

    return try sourceEdits(insertingAccessors: accessors, into: syntax)
  }

  private static func makeIsAccessor(
    name: String,
    casePattern: String,
    baseIndentation: Trivia,
    indentationStep: Trivia
  ) -> String {
    let memberIndentation = (baseIndentation + indentationStep).description
    let bodyIndentation = (baseIndentation + indentationStep + indentationStep).description
    return """
      \(memberIndentation)var \(name): Bool {
      \(bodyIndentation)if case .\(casePattern) = self { return true }
      \(bodyIndentation)return false
      \(memberIndentation)}
      """
  }
}

// MARK: - Shared helpers

private func enumCaseElements(of enumDecl: EnumDeclSyntax) -> [EnumCaseElementSyntax] {
  enumDecl.memberBlock.members.flatMap { member -> [EnumCaseElementSyntax] in
    guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return [] }
    return Array(caseDecl.elements)
  }
}

/// The `as`/`is` accessor name for a case, with the leading character upper-cased.
private func capitalizedCaseName(of element: EnumCaseElementSyntax) -> String {
  let caseName = element.name.identifier?.name ?? element.name.text
  return caseName.prefix(1).uppercased() + caseName.dropFirst()
}

/// Whether `type` must be parenthesized to be made optional. Types that the postfix `?` already
/// binds to are returned as-is; anything else (function, composition, `any`, attributed, … types)
/// is parenthesized so e.g. `(Int) -> Void` becomes `((Int) -> Void)?` rather than `(Int) -> Void?`.
private func needsParenthesesBeforeOptional(_ type: TypeSyntax) -> Bool {
  switch type.as(TypeSyntaxEnum.self) {
  case .identifierType, .memberType, .arrayType, .dictionaryType, .optionalType,
    .implicitlyUnwrappedOptionalType, .tupleType, .metatypeType:
    return false
  default:
    return true
  }
}

/// The enclosing enum's indentation and the file's inferred indentation step.
private func accessorIndentation(for enumDecl: EnumDeclSyntax) -> (base: Trivia, step: Trivia) {
  let base = enumDecl.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
  let step = BasicFormat.inferIndentation(of: enumDecl.root) ?? .spaces(4)
  return (base: base, step: step)
}

private func sourceEdits(insertingAccessors accessors: [String], into enumDecl: EnumDeclSyntax) throws -> [SourceEdit] {
  guard !accessors.isEmpty else {
    throw RefactoringNotApplicableError("No accessors to generate")
  }
  // Insert before the closing brace's leading trivia so the brace keeps its own
  // newline and indentation (correct for both top-level and nested enums).
  let insertion = "\n\n" + accessors.joined(separator: "\n\n")
  let position = enumDecl.memberBlock.rightBrace.position
  return [SourceEdit(range: position..<position, replacement: insertion)]
}
