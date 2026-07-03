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

/// Syntactic code action to toggle a test between enabled and disabled states.
///
/// ## Swift Testing
///
/// **Disable:**
/// ```swift
/// @Test
/// func checkArithmetic() { … }
/// ```
///
/// becomes:
///
/// ```swift
/// @Test(.disabled())
/// func checkArithmetic() { … }
/// ```
///
/// **Enable** (removing the `.disabled()` trait):
///
/// ```swift
/// @Test(.disabled())
/// func checkArithmetic() { … }
/// ```
///
/// becomes:
///
/// ```swift
/// @Test
/// func checkArithmetic() { … }
/// ```
///
/// ## XCTest
///
/// **Disable:**
///
/// ```swift
/// func testArithmetic() {
///     XCTAssertEqual(2 + 2, 4)
/// }
/// ```
///
/// becomes:
///
/// ```swift
/// func testArithmetic() throws {
///     throw XCTSkip("Disabled")
///     XCTAssertEqual(2 + 2, 4)
/// }
/// ```
///
/// **Enable:**
///
/// ```swift
/// func testArithmetic() throws {
///     throw XCTSkip("Disabled")
///     XCTAssertEqual(2 + 2, 4)
/// }
/// ```
///
/// becomes:
///
/// ```swift
/// func testArithmetic() {
///     XCTAssertEqual(2 + 2, 4)
/// }
/// ```
package struct ToggleTestDisabled: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let funcDecl = scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: FunctionDeclSyntax.self,
      stoppingIf: { $0.is(MemberBlockSyntax.self) || $0.is(SourceFileSyntax.self) }
    ) else { return [] }

    if let testAttr = swiftTestingAttribute(in: funcDecl) {
      return swiftTestingActions(testAttr: testAttr, scope: scope)
    }

    if isXCTestFunction(funcDecl) {
      return xcTestActions(funcDecl: funcDecl, scope: scope)
    }

    return []
  }

  // MARK: - Swift Testing

  /// Returns the `@Test` attribute if present on the function declaration.
  private static func swiftTestingAttribute(in funcDecl: FunctionDeclSyntax) -> AttributeSyntax? {
    funcDecl.attributes.lazy.compactMap { $0.as(AttributeSyntax.self) }.first {
      $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Test"
    }
  }

  private static func swiftTestingActions(
    testAttr: AttributeSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    let isDisabled = hasDisabledTrait(testAttr)
    let newAttr = isDisabled ? removeDisabledTrait(from: testAttr) : addDisabledTrait(to: testAttr)

    let edit = TextEdit(
      range: scope.snapshot.positionRange(of: testAttr.position..<testAttr.endPosition),
      newText: newAttr.description
    )
    return [
      CodeAction(
        title: isDisabled ? "Enable test" : "Disable test",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  /// Returns true if the `@Test` attribute contains a `.disabled(...)` trait.
  private static func hasDisabledTrait(_ attr: AttributeSyntax) -> Bool {
    guard let args = attr.arguments, case .argumentList(let list) = args else { return false }
    return list.contains { isDisabledCall($0.expression) }
  }

  /// Returns true if `expr` is a `.disabled(...)` member call.
  private static func isDisabledCall(_ expr: ExprSyntax) -> Bool {
    guard let call = expr.as(FunctionCallExprSyntax.self),
      let member = call.calledExpression.as(MemberAccessExprSyntax.self)
    else { return false }
    return member.declName.baseName.text == "disabled"
  }

  private static func addDisabledTrait(to attr: AttributeSyntax) -> AttributeSyntax {
    let disabled = FunctionCallExprSyntax(
      calledExpression: ExprSyntax(
        MemberAccessExprSyntax(
          base: nil,
          period: .periodToken(),
          declName: DeclReferenceExprSyntax(baseName: .identifier("disabled"))
        )
      ),
      leftParen: .leftParenToken(),
      arguments: LabeledExprListSyntax([]),
      rightParen: .rightParenToken()
    )
    let newArg = LabeledExprSyntax(expression: ExprSyntax(disabled))

    if let args = attr.arguments, case .argumentList(let existing) = args {
      if existing.isEmpty {
        // Parens present but empty - just insert the argument.
        return attr.with(\.arguments, .argumentList(LabeledExprListSyntax([newArg])))
      } else {
        // Append after existing arguments, adding a trailing comma to the last one.
        var newArgs = Array(existing)
        if var last = newArgs.last, last.trailingComma == nil {
          last.trailingComma = .commaToken(trailingTrivia: .space)
          newArgs[newArgs.count - 1] = last
        }
        newArgs.append(newArg)
        return attr.with(\.arguments, .argumentList(LabeledExprListSyntax(newArgs)))
      }
    } else {
      // No parens - add them together with the new argument.
      return attr
        .with(\.leftParen, .leftParenToken())
        .with(\.arguments, .argumentList(LabeledExprListSyntax([newArg])))
        .with(\.rightParen, .rightParenToken())
    }
  }

  private static func removeDisabledTrait(from attr: AttributeSyntax) -> AttributeSyntax {
    guard let args = attr.arguments, case .argumentList(let list) = args else { return attr }
    var filtered = Array(list.filter { !isDisabledCall($0.expression) })

    if filtered.isEmpty {
      // The disabled trait was the only argument - drop the parentheses too.
      return attr
        .with(\.leftParen, nil)
        .with(\.arguments, nil)
        .with(\.rightParen, nil)
    }

    // Remove stray trailing comma from the new last argument.
    if var last = filtered.last, last.trailingComma != nil {
      last.trailingComma = nil
      filtered[filtered.count - 1] = last
    }
    return attr.with(\.arguments, .argumentList(LabeledExprListSyntax(filtered)))
  }

  // MARK: - XCTest

  /// Returns true for functions whose names start with `test` and that take no parameters,
  /// which is the conventional signature for XCTest test methods.
  private static func isXCTestFunction(_ funcDecl: FunctionDeclSyntax) -> Bool {
    funcDecl.name.text.hasPrefix("test")
      && funcDecl.signature.parameterClause.parameters.isEmpty
      && swiftTestingAttribute(in: funcDecl) == nil
  }

  private static func xcTestActions(
    funcDecl: FunctionDeclSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    guard let body = funcDecl.body else { return [] }

    if let skip = body.statements.first, isXCTSkipStatement(skip) {
      return enableXCTestAction(funcDecl: funcDecl, body: body, skipStmt: skip, scope: scope)
    } else {
      return disableXCTestAction(funcDecl: funcDecl, body: body, scope: scope)
    }
  }

  private static func isXCTSkipStatement(_ item: CodeBlockItemSyntax) -> Bool {
    guard let throwStmt = item.item.as(ThrowStmtSyntax.self),
      let call = throwStmt.expression.as(FunctionCallExprSyntax.self),
      let ref = call.calledExpression.as(DeclReferenceExprSyntax.self)
    else { return false }
    return ref.baseName.text == "XCTSkip"
  }

  private static func disableXCTestAction(
    funcDecl: FunctionDeclSyntax,
    body: CodeBlockSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    var edits: [TextEdit] = []

    // Add `throws` to the signature if it is not already present.
    let sig = funcDecl.signature
    if sig.effectSpecifiers?.throwsClause == nil {
      let throwsClause = ThrowsClauseSyntax(
        throwsSpecifier: .keyword(.throws, leadingTrivia: .space)
      )
      let newSpecifiers: FunctionEffectSpecifiersSyntax
      if let existing = sig.effectSpecifiers {
        newSpecifiers = existing.with(\.throwsClause, throwsClause)
      } else {
        newSpecifiers = FunctionEffectSpecifiersSyntax(throwsClause: throwsClause)
      }
      let newSig = sig.with(\.effectSpecifiers, newSpecifiers)
      edits.append(TextEdit(
        range: scope.snapshot.positionRange(of: sig.position..<sig.endPosition),
        newText: newSig.description
      ))
    }

    // Determine the indentation from the first statement, falling back to 4 spaces.
    let indentation: String
    if let first = body.statements.first {
      let pieces = first.leadingTrivia.pieces
      var indentPieces: [TriviaPiece] = []
      for piece in pieces.reversed() {
        if piece.isNewline { break }
        indentPieces.insert(piece, at: 0)
      }
      indentation = Trivia(pieces: indentPieces).description
    } else {
      let funcIndent = funcDecl.firstToken(viewMode: .sourceAccurate)?.indentationOfLine.description ?? ""
      indentation = funcIndent + "    "
    }

    // Insert `throw XCTSkip("Disabled")` right after the opening brace.
    let insertPos = body.leftBrace.endPosition
    edits.append(TextEdit(
      range: scope.snapshot.positionRange(of: insertPos..<insertPos),
      newText: "\n\(indentation)throw XCTSkip(\"Disabled\")"
    ))

    return [
      CodeAction(
        title: "Disable test",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: edits])
      )
    ]
  }

  private static func enableXCTestAction(
    funcDecl: FunctionDeclSyntax,
    body: CodeBlockSyntax,
    skipStmt: CodeBlockItemSyntax,
    scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    var edits: [TextEdit] = []

    // Remove `throws` from the signature if no other throw statements remain in the body.
    let sig = funcDecl.signature
    if sig.effectSpecifiers?.throwsClause != nil {
      let remaining = body.statements.filter { $0.id != skipStmt.id }
      let hasOtherThrows = remaining.contains { bodyItemContainsThrow($0) }
      if !hasOtherThrows {
        let newSpecifiers: FunctionEffectSpecifiersSyntax?
        if let existing = sig.effectSpecifiers {
          let updated = existing.with(\.throwsClause, nil)
          newSpecifiers = updated.asyncSpecifier == nil ? nil : updated
        } else {
          newSpecifiers = nil
        }
        let newSig = sig.with(\.effectSpecifiers, newSpecifiers)
        edits.append(TextEdit(
          range: scope.snapshot.positionRange(of: sig.position..<sig.endPosition),
          newText: newSig.description
        ))
      }
    }

    // Remove the `throw XCTSkip(...)` statement (including its leading newline + indentation).
    edits.append(TextEdit(
      range: scope.snapshot.positionRange(of: skipStmt.position..<skipStmt.endPosition),
      newText: ""
    ))

    return [
      CodeAction(
        title: "Enable test",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: edits])
      )
    ]
  }

  /// Returns true if the given code block item contains any `throw` statement.
  private static func bodyItemContainsThrow(_ item: CodeBlockItemSyntax) -> Bool {
    class ThrowFinder: SyntaxVisitor {
      var found = false
      override func visit(_ node: ThrowStmtSyntax) -> SyntaxVisitorContinueKind {
        found = true
        return .skipChildren
      }
    }
    let finder = ThrowFinder(viewMode: .sourceAccurate)
    finder.walk(Syntax(item))
    return finder.found
  }
}
