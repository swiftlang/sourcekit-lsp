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

/// Syntactic code action provider to toggle a test function between
/// enabled and disabled states.
///
/// For Swift Testing (`@Test`):
/// - Disable: `@Test` → `@Test(.disabled())`
/// - Enable: `@Test(.disabled())` → `@Test`
///
/// For XCTest (`func testX()`):
/// - Disable: adds `throws` and inserts `throw XCTSkip("Disabled")` as the
///   first statement
/// - Enable: removes the leading `throw XCTSkip(...)` and `throws` if no
///   other throwing code remains
struct ToggleDisabledTest: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard
      let funcDecl = scope.innermostNodeContainingRange?.findParentOfSelf(
        ofType: FunctionDeclSyntax.self,
        stoppingIf: { $0.is(CodeBlockSyntax.self) }
      )
    else {
      return []
    }

    if let action = swiftTestingAction(for: funcDecl, scope: scope) {
      return [action]
    }
    if let action = xcTestAction(for: funcDecl, scope: scope) {
      return [action]
    }
    return []
  }

  // MARK: - Swift Testing

  private static func swiftTestingAction(
    for funcDecl: FunctionDeclSyntax,
    scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    guard let testAttribute = findTestAttribute(on: funcDecl) else {
      return nil
    }

    if let disabledIndex = findUnconditionalDisabledTraitIndex(in: testAttribute) {
      return enableSwiftTestingAction(
        testAttribute: testAttribute,
        disabledIndex: disabledIndex,
        scope: scope
      )
    } else {
      return disableSwiftTestingAction(
        testAttribute: testAttribute,
        scope: scope
      )
    }
  }

  /// Find the `@Test` attribute on a function declaration.
  private static func findTestAttribute(
    on funcDecl: FunctionDeclSyntax
  ) -> AttributeSyntax? {
    funcDecl.attributes.lazy
      .compactMap { $0.as(AttributeSyntax.self) }
      .first { attribute in
        if let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) {
          return identifier.name.text == "Test"
        }
        if let member = attribute.attributeName.as(MemberTypeSyntax.self),
          let base = member.baseType.as(IdentifierTypeSyntax.self)
        {
          return member.name.text == "Test" && base.name.text == "Testing"
        }
        return false
      }
  }

  /// Find the index of an unconditional `.disabled()` trait in the attribute's
  /// argument list. Returns `nil` if none is found.
  private static func findUnconditionalDisabledTraitIndex(
    in attribute: AttributeSyntax
  ) -> Int? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
      return nil
    }

    for (index, arg) in arguments.enumerated() {
      guard
        let functionCall = arg.expression.as(FunctionCallExprSyntax.self),
        let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
        isDisabledName(memberAccess)
      else {
        continue
      }

      // Ignore conditional disables (those with `if:` parameter or trailing closure).
      let hasCondition = functionCall.arguments.contains { $0.label?.text == "if" }
      if hasCondition || functionCall.trailingClosure != nil {
        continue
      }

      return index
    }
    return nil
  }

  /// Check whether a member access expression refers to `disabled`,
  /// `ConditionTrait.disabled`, or `Testing.ConditionTrait.disabled`.
  private static func isDisabledName(_ expr: MemberAccessExprSyntax) -> Bool {
    let name = qualifiedName(of: expr)
    switch name {
    case "disabled", "ConditionTrait.disabled", "Testing.ConditionTrait.disabled":
      return true
    default:
      return false
    }
  }

  /// Build the dot-separated qualified name of a member access expression.
  private static func qualifiedName(of expr: MemberAccessExprSyntax) -> String {
    var components: [String] = []
    var current: ExprSyntax? = ExprSyntax(expr)
    while let memberAccess = current?.as(MemberAccessExprSyntax.self) {
      components.append(memberAccess.declName.baseName.text)
      current = memberAccess.base
    }
    if let declRef = current?.as(DeclReferenceExprSyntax.self) {
      components.append(declRef.baseName.text)
    }
    return components.reversed().joined(separator: ".")
  }

  // MARK: Disable Swift Testing

  /// Range covering only the textual content of the attribute (no trivia).
  private static func trimmedRange(
    of node: some SyntaxProtocol,
    in snapshot: DocumentSnapshot
  ) -> Range<Position> {
    snapshot.absolutePositionRange(
      of: node.positionAfterSkippingLeadingTrivia..<node.endPositionBeforeTrailingTrivia
    )
  }

  private static func disableSwiftTestingAction(
    testAttribute: AttributeSyntax,
    scope: SyntaxCodeActionScope
  ) -> CodeAction {
    let newText = buildDisabledAttributeText(testAttribute: testAttribute)
    let edit = TextEdit(
      range: trimmedRange(of: testAttribute, in: scope.snapshot),
      newText: newText
    )
    return CodeAction(
      title: "Disable test",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
    )
  }

  /// Build the replacement text for a `@Test` attribute with `.disabled()` added.
  private static func buildDisabledAttributeText(
    testAttribute: AttributeSyntax
  ) -> String {
    let attrName = testAttribute.attributeName.trimmedDescription
    guard let arguments = testAttribute.arguments?.as(LabeledExprListSyntax.self),
      !arguments.isEmpty
    else {
      return "@\(attrName)(.disabled())"
    }

    let argTexts = arguments.map { $0.expression.trimmedDescription }

    // If the first argument is an unlabeled string literal (display name),
    // insert .disabled() after it. Otherwise insert at the beginning.
    let firstArg = arguments.first!
    let isDisplayName =
      firstArg.label == nil
      && firstArg.expression.is(StringLiteralExprSyntax.self)

    var parts: [String]
    if isDisplayName {
      parts = [argTexts[0], ".disabled()"] + argTexts.dropFirst()
    } else {
      parts = [".disabled()"] + argTexts
    }
    return "@\(attrName)(\(parts.joined(separator: ", ")))"
  }

  // MARK: Enable Swift Testing

  private static func enableSwiftTestingAction(
    testAttribute: AttributeSyntax,
    disabledIndex: Int,
    scope: SyntaxCodeActionScope
  ) -> CodeAction {
    let newText = buildEnabledAttributeText(
      testAttribute: testAttribute,
      disabledIndex: disabledIndex
    )
    let edit = TextEdit(
      range: trimmedRange(of: testAttribute, in: scope.snapshot),
      newText: newText
    )
    return CodeAction(
      title: "Enable test",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
    )
  }

  /// Build the replacement text for a `@Test` attribute with `.disabled()` removed.
  private static func buildEnabledAttributeText(
    testAttribute: AttributeSyntax,
    disabledIndex: Int
  ) -> String {
    let attrName = testAttribute.attributeName.trimmedDescription
    guard let arguments = testAttribute.arguments?.as(LabeledExprListSyntax.self) else {
      return "@\(attrName)"
    }

    let remaining = arguments.enumerated()
      .filter { $0.offset != disabledIndex }
      .map { $0.element.expression.trimmedDescription }

    if remaining.isEmpty {
      return "@\(attrName)"
    }
    return "@\(attrName)(\(remaining.joined(separator: ", ")))"
  }

  // MARK: - XCTest

  private static func xcTestAction(
    for funcDecl: FunctionDeclSyntax,
    scope: SyntaxCodeActionScope
  ) -> CodeAction? {
    let name = funcDecl.name.text
    guard name.hasPrefix("test") else {
      return nil
    }

    // XCTest methods must be inside a class or extension.
    guard isDirectClassOrExtensionMember(funcDecl) else {
      return nil
    }

    guard funcDecl.body != nil else {
      return nil
    }

    if hasLeadingXCTSkip(funcDecl) {
      return enableXCTestAction(for: funcDecl, scope: scope)
    } else {
      return disableXCTestAction(for: funcDecl, scope: scope)
    }
  }

  /// Check whether the function is a direct member of a class or extension.
  private static func isDirectClassOrExtensionMember(
    _ funcDecl: FunctionDeclSyntax
  ) -> Bool {
    // Walk up to find the enclosing MemberBlockSyntax, then check its parent.
    var node: Syntax? = Syntax(funcDecl).parent
    while let current = node {
      if let memberBlock = current.as(MemberBlockSyntax.self) {
        let parent = memberBlock.parent
        return parent?.is(ClassDeclSyntax.self) == true
          || parent?.is(ExtensionDeclSyntax.self) == true
      }
      // Stop at code blocks to avoid matching nested functions.
      if current.is(CodeBlockSyntax.self) {
        return false
      }
      node = current.parent
    }
    return false
  }

  /// Check whether the first statement in the function body is
  /// `throw XCTSkip(...)`.
  private static func hasLeadingXCTSkip(_ funcDecl: FunctionDeclSyntax) -> Bool {
    guard
      let firstItem = funcDecl.body?.statements.first,
      let throwStmt = firstItem.item.as(ThrowStmtSyntax.self),
      let functionCall = throwStmt.expression.as(FunctionCallExprSyntax.self)
    else {
      return false
    }

    if let declRef = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
      return declRef.baseName.text == "XCTSkip"
    }
    if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
      return memberAccess.declName.baseName.text == "XCTSkip"
    }
    return false
  }

  // MARK: Disable XCTest

  private static func disableXCTestAction(
    for funcDecl: FunctionDeclSyntax,
    scope: SyntaxCodeActionScope
  ) -> CodeAction {
    var edits: [TextEdit] = []

    // Add `throws` to the signature if not already present.
    if funcDecl.signature.effectSpecifiers?.throwsClause == nil {
      let insertPosition = funcDecl.signature.parameterClause.endPositionBeforeTrailingTrivia
      edits.append(
        TextEdit(
          range: scope.snapshot.absolutePositionRange(of: insertPosition..<insertPosition),
          newText: " throws"
        )
      )
    }

    // Insert `throw XCTSkip("Disabled")` as the first statement.
    if let body = funcDecl.body {
      let indent = inferIndentation(of: body)
      let skipStatement = "\(indent)throw XCTSkip(\"Disabled\")"

      let insertPos = body.leftBrace.endPositionBeforeTrailingTrivia
      edits.append(
        TextEdit(
          range: scope.snapshot.absolutePositionRange(of: insertPos..<insertPos),
          newText: "\n\(skipStatement)"
        )
      )
    }

    return CodeAction(
      title: "Disable test",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [scope.snapshot.uri: edits])
    )
  }

  // MARK: Enable XCTest

  private static func enableXCTestAction(
    for funcDecl: FunctionDeclSyntax,
    scope: SyntaxCodeActionScope
  ) -> CodeAction {
    var edits: [TextEdit] = []

    // Remove the leading `throw XCTSkip(...)` statement.
    if let body = funcDecl.body, let firstItem = body.statements.first {
      let statements = Array(body.statements)
      if statements.count > 1 {
        // Remove from the start of the first item to the start of the second.
        let removeRange = firstItem.position..<statements[1].position
        edits.append(
          TextEdit(
            range: scope.snapshot.absolutePositionRange(of: removeRange),
            newText: ""
          )
        )
      } else {
        // Only statement - remove it but leave the braces.
        let removeRange = firstItem.position..<firstItem.endPosition
        edits.append(
          TextEdit(
            range: scope.snapshot.absolutePositionRange(of: removeRange),
            newText: ""
          )
        )
      }
    }

    // Remove `throws` if no other throwing code remains.
    if let throwsClause = funcDecl.signature.effectSpecifiers?.throwsClause,
      !hasOtherThrowingCode(in: funcDecl)
    {
      // Remove the throws keyword and its trailing space.
      let removeStart = throwsClause.position
      let removeEnd = throwsClause.endPosition
      edits.append(
        TextEdit(
          range: scope.snapshot.absolutePositionRange(of: removeStart..<removeEnd),
          newText: ""
        )
      )
    }

    return CodeAction(
      title: "Enable test",
      kind: .refactorInline,
      edit: WorkspaceEdit(changes: [scope.snapshot.uri: edits])
    )
  }

  // MARK: - Helpers

  /// Infer the indentation used inside a code block by examining the first
  /// statement's leading trivia, or falling back to 4 spaces.
  private static func inferIndentation(of body: CodeBlockSyntax) -> String {
    if let firstItem = body.statements.first {
      let trivia = firstItem.leadingTrivia
      var indent = ""
      var sawNewline = false
      for piece in trivia.pieces {
        switch piece {
        case .newlines, .carriageReturns, .carriageReturnLineFeeds:
          sawNewline = true
          indent = ""
        case .spaces(let count):
          if sawNewline { indent += String(repeating: " ", count: count) }
        case .tabs(let count):
          if sawNewline { indent += String(repeating: "\t", count: count) }
        default:
          break
        }
      }
      if !indent.isEmpty {
        return indent
      }
    }
    return "    "
  }

  /// Check whether the function body contains throwing code beyond the first
  /// `throw XCTSkip(...)` statement. This checks for `throw` statements and
  /// `try` expressions in remaining statements, without descending into nested
  /// functions or closures.
  private static func hasOtherThrowingCode(in funcDecl: FunctionDeclSyntax) -> Bool {
    guard let body = funcDecl.body else { return false }
    let statements = Array(body.statements.dropFirst())
    for stmt in statements {
      if containsThrowOrTry(Syntax(stmt)) {
        return true
      }
    }
    return false
  }

  /// Recursively check whether a syntax node contains a `throw` statement or
  /// `try` expression, stopping at function or closure boundaries.
  private static func containsThrowOrTry(_ node: Syntax) -> Bool {
    if node.is(ThrowStmtSyntax.self) || node.is(TryExprSyntax.self) {
      return true
    }
    // Don't descend into nested functions or closures.
    if node.is(FunctionDeclSyntax.self) || node.is(ClosureExprSyntax.self) {
      return false
    }
    for child in node.children(viewMode: .sourceAccurate) {
      if containsThrowOrTry(child) {
        return true
      }
    }
    return false
  }
}
