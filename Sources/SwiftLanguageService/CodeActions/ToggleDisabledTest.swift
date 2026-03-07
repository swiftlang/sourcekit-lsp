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

/// A code action that toggles a test between enabled and disabled states.
///
/// **Swift Testing:**
/// - `@Test func ...` ↔ `@Test(.disabled()) func ...`
///
/// **XCTest:**
/// - `func testExample()` ↔ `func testExample() throws { throw XCTSkip("Disabled") ... }`
struct ToggleDisabledTest: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = scope.innermostNodeContainingRange else {
      return []
    }

    guard let funcDecl = node.findParentOfSelf(
      ofType: FunctionDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) }
    ) else {
      return []
    }

    // Try Swift Testing first, then XCTest.
    if let result = trySwiftTesting(funcDecl: funcDecl, scope: scope) {
      return result
    }
    if let result = tryXCTest(funcDecl: funcDecl, scope: scope) {
      return result
    }

    return []
  }

  // MARK: - Swift Testing

  private static func trySwiftTesting(
    funcDecl: FunctionDeclSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction]? {
    // Find @Test attribute.
    guard let testAttr = funcDecl.attributes.first(where: { attr in
      if case let .attribute(a) = attr,
         a.attributeName.trimmedDescription == "Test" {
        return true
      }
      return false
    }) else {
      return nil
    }

    guard case let .attribute(attr) = testAttr else { return nil }

    let isDisabled = hasDisabledTrait(attr)

    if isDisabled {
      // Remove .disabled() trait — enable the test.
      let newAttr = removeDisabledTrait(attr)
      let title = "Enable test"

      return [
        CodeAction(
          title: title,
          kind: .refactorInline,
          edit: WorkspaceEdit(
            changes: [
              scope.snapshot.uri: [
                TextEdit(
                  range: Range(
                    uncheckedBounds: (
                      lower: scope.snapshot.position(of: attr.positionAfterSkippingLeadingTrivia),
                      upper: scope.snapshot.position(of: attr.endPositionBeforeTrailingTrivia)
                    )
                  ),
                  newText: newAttr
                )
              ]
            ]
          )
        )
      ]
    } else {
      // Add .disabled() trait — disable the test.
      let newAttr = addDisabledTrait(attr)
      let title = "Disable test"

      return [
        CodeAction(
          title: title,
          kind: .refactorInline,
          edit: WorkspaceEdit(
            changes: [
              scope.snapshot.uri: [
                TextEdit(
                  range: Range(
                    uncheckedBounds: (
                      lower: scope.snapshot.position(of: attr.positionAfterSkippingLeadingTrivia),
                      upper: scope.snapshot.position(of: attr.endPositionBeforeTrailingTrivia)
                    )
                  ),
                  newText: newAttr
                )
              ]
            ]
          )
        )
      ]
    }
  }

  /// Check if an @Test attribute contains a `.disabled()` trait.
  private static func hasDisabledTrait(_ attr: AttributeSyntax) -> Bool {
    guard let arguments = attr.arguments,
          case let .argumentList(argList) = arguments
    else {
      return false
    }

    return argList.contains { arg in
      if let memberAccess = arg.expression.as(FunctionCallExprSyntax.self),
         let calledExpr = memberAccess.calledExpression.as(MemberAccessExprSyntax.self),
         calledExpr.declName.baseName.text == "disabled" {
        return true
      }
      if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self),
         memberAccess.declName.baseName.text == "disabled" {
        return true
      }
      return false
    }
  }

  /// Remove `.disabled()` from @Test arguments.
  private static func removeDisabledTrait(_ attr: AttributeSyntax) -> String {
    guard let arguments = attr.arguments,
          case let .argumentList(argList) = arguments
    else {
      return attr.trimmedDescription
    }

    let remaining = argList.filter { arg in
      if let memberAccess = arg.expression.as(FunctionCallExprSyntax.self),
         let calledExpr = memberAccess.calledExpression.as(MemberAccessExprSyntax.self),
         calledExpr.declName.baseName.text == "disabled" {
        return false
      }
      if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self),
         memberAccess.declName.baseName.text == "disabled" {
        return false
      }
      return true
    }

    if remaining.isEmpty {
      return "@Test"
    }

    // Rebuild argument list without trailing comma on the last element.
    var newArgs: [LabeledExprSyntax] = Array(remaining)
    if let last = newArgs.last {
      newArgs[newArgs.count - 1] = last.with(\.trailingComma, nil)
    }

    let argListText = newArgs.map { $0.trimmedDescription }.joined(separator: ", ")
    return "@Test(\(argListText))"
  }

  /// Add `.disabled()` to @Test arguments.
  private static func addDisabledTrait(_ attr: AttributeSyntax) -> String {
    if let arguments = attr.arguments,
       case let .argumentList(argList) = arguments,
       !argList.isEmpty {
      let existingArgs = argList.map { $0.trimmedDescription }.joined(separator: ", ")
      return "@Test(\(existingArgs), .disabled())"
    }
    return "@Test(.disabled())"
  }

  // MARK: - XCTest

  private static func tryXCTest(
    funcDecl: FunctionDeclSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction]? {
    let funcName = funcDecl.name.text
    guard funcName.hasPrefix("test") else { return nil }

    // Check if the function body starts with `throw XCTSkip`.
    guard let body = funcDecl.body else { return nil }
    let statements = Array(body.statements)

    let hasXCTSkip = statements.first.map { stmt -> Bool in
      if let throwStmt = stmt.item.as(ThrowStmtSyntax.self),
         let callExpr = throwStmt.expression.as(FunctionCallExprSyntax.self),
         let calledExpr = callExpr.calledExpression.as(DeclReferenceExprSyntax.self),
         calledExpr.baseName.text == "XCTSkip" {
        return true
      }
      return false
    } ?? false

    if hasXCTSkip {
      // Enable: remove the throw XCTSkip line and optionally remove `throws`.
      let remainingStatements = Array(statements.dropFirst())
      let remainingText = remainingStatements.map { $0.trimmedDescription }.joined(separator: "\n    ")

      // Rebuild the function signature without `throws` if it was only for XCTSkip.
      var newFunc = funcDecl.trimmedDescription
      // Replace the entire function.
      let newSignature: String
      let effectSpecifiers = funcDecl.signature.effectSpecifiers
      let hadThrows = effectSpecifiers?.throwsClause != nil

      // Build new signature.
      let paramList = funcDecl.signature.parameterClause.trimmedDescription
      let returnClause = funcDecl.signature.returnClause?.trimmedDescription ?? ""
      if hadThrows && remainingStatements.allSatisfy({ !$0.trimmedDescription.contains("throw") }) {
        newSignature = "func \(funcName)\(paramList)\(returnClause.isEmpty ? "" : " \(returnClause)")"
      } else {
        newSignature = "func \(funcName)\(paramList) throws\(returnClause.isEmpty ? "" : " \(returnClause)")"
      }

      let bodyText: String
      if remainingStatements.isEmpty {
        bodyText = " {\n    }"
      } else {
        bodyText = " {\n    \(remainingText)\n    }"
      }

      newFunc = newSignature + bodyText

      return [
        CodeAction(
          title: "Enable test",
          kind: .refactorInline,
          edit: WorkspaceEdit(
            changes: [
              scope.snapshot.uri: [
                TextEdit(
                  range: Range(
                    uncheckedBounds: (
                      lower: scope.snapshot.position(of: funcDecl.positionAfterSkippingLeadingTrivia),
                      upper: scope.snapshot.position(of: funcDecl.endPositionBeforeTrailingTrivia)
                    )
                  ),
                  newText: newFunc
                )
              ]
            ]
          )
        )
      ]
    } else {
      // Disable: add `throws` and `throw XCTSkip("Disabled")` at the top.
      let existingStatements = statements.map { "    \($0.trimmedDescription)" }.joined(separator: "\n")
      let paramList = funcDecl.signature.parameterClause.trimmedDescription
      let returnClause = funcDecl.signature.returnClause?.trimmedDescription ?? ""
      let effectSpecifiers = funcDecl.signature.effectSpecifiers
      let isAsync = effectSpecifiers?.asyncSpecifier != nil

      let effectsText = isAsync ? " async throws" : " throws"

      let newFunc =
        "func \(funcName)\(paramList)\(effectsText)\(returnClause.isEmpty ? "" : " \(returnClause)") {\n    throw XCTSkip(\"Disabled\")\n\(existingStatements)\n    }"

      return [
        CodeAction(
          title: "Disable test",
          kind: .refactorInline,
          edit: WorkspaceEdit(
            changes: [
              scope.snapshot.uri: [
                TextEdit(
                  range: Range(
                    uncheckedBounds: (
                      lower: scope.snapshot.position(of: funcDecl.positionAfterSkippingLeadingTrivia),
                      upper: scope.snapshot.position(of: funcDecl.endPositionBeforeTrailingTrivia)
                    )
                  ),
                  newText: newFunc
                )
              ]
            ]
          )
        )
      ]
    }
  }
}
