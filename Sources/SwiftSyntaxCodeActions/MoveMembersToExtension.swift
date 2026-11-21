//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project.
//
// Copyright 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception.
//
// See https://swift.org/LICENSE.txt for license information.
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors.
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SourceKitLSP
import SwiftBasicFormat
import SwiftExtensions
import SwiftSyntax
import SwiftSyntaxBuilder

/// Syntactic code action provider to move a member declaration of a
/// top-level struct, class, or enum into an extension of that type.
///
/// ## Before
/// ```swift
/// struct Counter {
///   func increment() {}
/// }
/// ```
///
/// ## After
/// ```swift
/// struct Counter {
/// }
///
/// extension Counter {
///   func increment() {}
/// }
/// ```
@_spi(Testing) public struct MoveMembersToExtension: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let member = findMovableMember(in: scope) else {
      return []
    }

    let memberText = member.member.trimmedDescription
    let memberIndent = member.member.leadingTrivia.pieces.reversed().prefix { piece in
      switch piece {
      case .spaces, .tabs: return true
      default: return false
      }
    }.reduce(into: 0) { count, piece in count += piece.sourceLength.utf8Length }
    // trimmedDescription drops the member's leading indentation; restore
    // the extension body's two-space indent on the first line. Nested
    // lines keep their original absolute indentation, which matches the
    // member being re-hosted at the same depth in the extension.
    let indent = String(repeating: " ", count: memberIndent)
    let lines = memberText.split(separator: "\n", omittingEmptySubsequences: false)
    var indentedLines = lines.map { String($0) }
    if let first = indentedLines.first {
      indentedLines[0] = indent + first
    }
    let indentedMemberText = indentedLines.joined(separator: "\n")
    let extensionText = "\n\nextension \(member.typeName) {\n\(indentedMemberText)\n}"

    // Remove the whole line the member occupies, including its leading
    // indentation and trailing newline.
    let start = member.member.positionAfterSkippingLeadingTrivia.advanced(by: -memberIndent)
    let trailingLength = member.member.trailingTrivia.sourceLength.utf8Length
    let removeRange =
      scope.snapshot.positionRange(
        of: start..<member.member.endPosition.advanced(by: trailingLength)
      )
    let insertionPosition = scope.snapshot.position(
      of: member.typeDecl.endPosition
    )
    let edits = [
      TextEdit(range: removeRange, newText: ""),
      TextEdit(range: insertionPosition..<insertionPosition, newText: extensionText),
    ]

    return [
      CodeAction(
        title: "Move to extension",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: edits])
      )
    ]
  }

  struct MovableMember {
    let typeDecl: any NamedDeclSyntax
    let typeName: String
    let member: MemberBlockItemSyntax
  }

  /// Walks up from the cursor to find a member declaration that can be
  /// moved into an extension of its enclosing top-level type.
  static func findMovableMember(in scope: SyntaxCodeActionScope) -> MovableMember? {
    guard let innermost = scope.innermostNodeContainingRange else {
      return nil
    }

    var node: Syntax? = Syntax(innermost)
    while let current = node {
      if let memberItem = current.as(MemberBlockItemSyntax.self) {
        return movableMember(for: memberItem)
      }
      if current.is(DeclSyntax.self) {
        // The cursor may sit inside the member's declaration rather than
        // the member-block item itself.
        if let memberItem = current.parent?.as(MemberBlockItemSyntax.self) {
          return movableMember(for: memberItem)
        }
        return nil
      }
      node = current.parent
    }
    return nil
  }

  static func movableMember(for memberItem: MemberBlockItemSyntax) -> MovableMember? {
    guard let memberBlock = memberItem.parent?.as(MemberBlockItemListSyntax.self)?.parent?
      .as(MemberBlockSyntax.self) ?? memberItem.parent?.as(MemberBlockSyntax.self)
    else {
      return nil
    }
    // Only top-level struct, class, or enum declarations.
    guard let typeDecl = typeDecl(of: memberBlock), isTopLevel(typeDecl) else {
      return nil
    }

    guard isMovable(memberItem.decl) else {
      return nil
    }

    return MovableMember(typeDecl: typeDecl, typeName: typeDecl.name.text, member: memberItem)
  }

  /// The struct, class, or enum that owns `memberBlock`, or `nil` if the
  /// block belongs to another declaration kind.
  static func typeDecl(of memberBlock: MemberBlockSyntax) -> (any NamedDeclSyntax)? {
    let decl = memberBlock.parent?.as(DeclSyntax.self)
    if let structDecl = decl?.as(StructDeclSyntax.self) {
      return structDecl
    }
    if let classDecl = decl?.as(ClassDeclSyntax.self) {
      return classDecl
    }
    if let enumDecl = decl?.as(EnumDeclSyntax.self) {
      return enumDecl
    }
    return nil
  }

  /// Whether the type declaration is declared at the top level of a file
  /// (its parent chain goes directly through a code block item of the
  /// source file).
  static func isTopLevel(_ typeDecl: some SyntaxProtocol) -> Bool {
    var parent = typeDecl.parent
    // Unwrap the code block item list and item wrappers.
    while let current = parent {
      if current.is(CodeBlockItemListSyntax.self) || current.is(CodeBlockItemSyntax.self) {
        parent = current.parent
        continue
      }
      break
    }
    // The source file node has no parent.
    return parent == nil || parent?.is(SourceFileSyntax.self) == true
  }

  /// Whether the member declaration is allowed inside an extension.
  static func isMovable(_ decl: DeclSyntax) -> Bool {
    if decl.is(FunctionDeclSyntax.self) || decl.is(InitializerDeclSyntax.self)
      || decl.is(SubscriptDeclSyntax.self) || decl.is(TypeAliasDeclSyntax.self)
    {
      return true
    }
    if let variable = decl.as(VariableDeclSyntax.self) {
      // Stored properties (with an initializer) cannot be declared in an
      // extension; computed properties can.
      for binding in variable.bindings {
        if binding.initializer != nil {
          return false
        }
      }
      return true
    }
    return false
  }
}
