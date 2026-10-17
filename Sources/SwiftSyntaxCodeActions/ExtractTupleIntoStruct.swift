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
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftRefactor
package import SwiftSyntax

/// Syntactic code action that extracts a named tuple type into a named struct.
///
/// When the cursor is on a named tuple type — one where every element carries a
/// label — this action generates a `struct` definition with matching stored
/// properties immediately before the enclosing declaration, then replaces the
/// tuple type annotation with the new struct name.
///
/// Only the local type annotation is rewritten. Renaming call sites that
/// construct or destructure the tuple is left to a follow-up rename refactoring.
///
/// ## Before
///
/// ```swift
/// func getUser() -> (name: String, age: Int, email: String) {
///     return ("Alice", 30, "alice@example.com")
/// }
/// ```
///
/// ## After
///
/// ```swift
/// struct GetUserResult {
///     let name: String
///     let age: Int
///     let email: String
/// }
///
/// func getUser() -> GetUserResult {
///     return ("Alice", 30, "alice@example.com")
/// }
/// ```
struct ExtractTupleIntoStruct: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let tupleType = findNamedTupleType(in: scope) else {
      return []
    }
    guard let enclosingDecl = findEnclosingInsertionPoint(of: Syntax(tupleType)) else {
      return []
    }

    let structName = deriveStructName(for: tupleType)

    // Match the indentation style of the surrounding source.
    let indentStep = BasicFormat.inferIndentation(of: tupleType.root) ?? .spaces(4)
    let baseIndentation = enclosingDecl.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    let memberIndent = (baseIndentation + indentStep).description
    let baseIndent = baseIndentation.description

    // Build each stored property line. All elements are guaranteed to have
    // non-wildcard labels because findNamedTupleType enforces that.
    let fields = tupleType.elements.map { element in
      "\(memberIndent)let \(element.firstName!.text): \(element.type.trimmedDescription)"
    }.joined(separator: "\n")

    // Insert right before the first real token of the enclosing declaration
    // (after its leading trivia). The trivia — typically a leading newline and
    // the declaration's indentation — becomes the struct's own prefix, so the
    // struct text itself omits an explicit leading indent but includes a
    // trailing blank line and indentation to restore spacing before the
    // original declaration.
    let insertPos = enclosingDecl.positionAfterSkippingLeadingTrivia
    let structText = "struct \(structName) {\n\(fields)\n\(baseIndent)}\n\n\(baseIndent)"
    let insertEdit = SourceEdit(range: insertPos..<insertPos, replacement: structText)

    // Replace the tuple type annotation with just the struct name.
    let replaceEdit = SourceEdit(
      range: tupleType.position..<tupleType.endPosition,
      replacement: structName
    )

    guard let workspaceEdit = [insertEdit, replaceEdit].asWorkspaceEdit(snapshot: scope.snapshot) else {
      return []
    }

    return [
      CodeAction(
        title: "Extract tuple into struct '\(structName)'",
        kind: .refactorExtract,
        edit: workspaceEdit
      )
    ]
  }
}

// MARK: - Finding the named tuple type

/// Returns the innermost named tuple type that contains the cursor range.
///
/// A tuple qualifies when it has at least two elements and every element
/// carries a non-wildcard label. Single-element tuples and unlabelled tuples
/// do not benefit from extraction because there is no clean way to name the
/// struct's properties.
private func findNamedTupleType(in scope: SyntaxCodeActionScope) -> TupleTypeSyntax? {
  scope.innermostNodeContainingRange?.findParentOfSelf(
    ofType: TupleTypeSyntax.self,
    stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) },
    matching: { tuple in
      guard tuple.elements.count >= 2 else { return false }
      return tuple.elements.allSatisfy { elem in
        guard let label = elem.firstName else { return false }
        return label.text != "_"
      }
    }
  )
}

// MARK: - Locating the insertion point

/// Walks up the syntax tree to find the nearest `DeclSyntax` that is a direct
/// child of a `CodeBlockItemSyntax` or `MemberBlockItemSyntax`.
///
/// That structural property means a new sibling declaration can be inserted
/// immediately before it, either at the top level of a function body or as a
/// nested member of a type.
private func findEnclosingInsertionPoint(of node: Syntax) -> DeclSyntax? {
  var current: Syntax? = node
  while let n = current {
    if let decl = n.as(DeclSyntax.self) {
      let parent = n.parent
      if parent?.is(CodeBlockItemSyntax.self) == true
        || parent?.is(MemberBlockItemSyntax.self) == true
      {
        return decl
      }
    }
    current = n.parent
  }
  return nil
}

// MARK: - Deriving a struct name

/// Infers a PascalCase struct name from the syntactic context of the tuple.
///
/// Priority:
/// 1. Function return type  → `<FunctionName>Result`  (e.g. `getUser` → `GetUserResult`)
/// 2. Variable annotation   → first-letter-capitalised variable name
/// 3. Type alias            → the alias name itself
/// 4. Fallback              → concatenated capitalised element labels
private func deriveStructName(for tupleType: TupleTypeSyntax) -> String {
  let node = Syntax(tupleType)
  let stop: (Syntax) -> Bool = {
    $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self)
  }

  // 1. Function return type — confirm the tuple lives inside the return clause,
  //    not inside the function body.
  if let funcDecl = node.findParentOfSelf(ofType: FunctionDeclSyntax.self, stoppingIf: stop),
    let returnType = funcDecl.signature.returnClause?.type,
    returnType.position <= tupleType.position,
    tupleType.endPosition <= returnType.endPosition
  {
    return uppercasedFirst(funcDecl.name.text) + "Result"
  }

  // 2. Variable / let / var type annotation.
  if let binding = node.findParentOfSelf(ofType: PatternBindingSyntax.self, stoppingIf: stop),
    let id = binding.pattern.as(IdentifierPatternSyntax.self)
  {
    return uppercasedFirst(id.identifier.text)
  }

  // 3. Type alias — keep the alias name as the struct name so the typealias can
  //    simply be removed after the extraction.
  if let alias = node.findParentOfSelf(ofType: TypeAliasDeclSyntax.self, stoppingIf: stop) {
    return alias.name.text
  }

  // 4. Fallback: join capitalised element labels (e.g. `(x, y)` → `XY`).
  let joined = tupleType.elements
    .compactMap { $0.firstName?.text }
    .map { uppercasedFirst($0) }
    .joined()
  return joined.isEmpty ? "TupleResult" : joined
}

private func uppercasedFirst(_ s: String) -> String {
  guard let first = s.first else { return s }
  return first.uppercased() + s.dropFirst()
}
