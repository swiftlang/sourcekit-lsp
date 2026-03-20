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

@_spi(RawSyntax) import SwiftSyntax
import SwiftRefactor
@_spi(SourceKitLSP) import LanguageServerProtocol

private enum ValidationResult: CustomStringConvertible {
  case accessor
  case deinitializer
  case enumCase
  case storedProperty

  var description: String {
    switch self {
    case .accessor: return "accessor"
    case .deinitializer: return "deinitializer"
    case .enumCase: return "enum case"
    case .storedProperty: return "stored property"
    }
  }

  /// Validates that `member` can be moved to an extension. If it can, return `nil`, otherwise return the reason why
  /// `member` cannot be moved to an extension.
  init?(_ member: MemberBlockItemSyntax) {
    switch member.decl.kind {
    case .accessorDecl:
      self = .accessor
    case .deinitializerDecl:
      self = .deinitializer
    case .enumCaseDecl:
      self = .enumCase
    default:
      if let varDecl = member.decl.as(VariableDeclSyntax.self),
         varDecl.bindings.contains(where: { $0.accessorBlock == nil || $0.initializer != nil })
      {
        self = .storedProperty
      }

      return nil
    }
  }
}

struct MoveMembersToExtension: SyntaxRefactoringProvider {
  struct Context {
    let range: Range<AbsolutePosition>

    init(range: Range<AbsolutePosition>) {
      self.range = range
    }
  }

  static func refactor(syntax: SourceFileSyntax, in context: Context) throws -> SourceFileSyntax {
    guard
      let statement = syntax.statements.first(where: { $0.item.range.contains(context.range) }),
      let decl = statement.item.asProtocol((any NamedDeclSyntax).self),
      let declGroup = statement.item.asProtocol((any DeclGroupSyntax).self),
      let statementIndex = syntax.statements.index(of: statement)
    else {
      throw RefactoringNotApplicableError("Type declaration not found")
    }

    let selectedMembers = Array(declGroup.memberBlock.members).filter { context.range.overlaps($0.trimmedRange) }
        .map { (member: $0, validationResult: ValidationResult($0)) }

    var membersToMove = selectedMembers.filter({ $0.validationResult == nil }).map(\.member)

    guard !membersToMove.isEmpty else {
      throw RefactoringNotApplicableError(
        "Cannot move \(Set(selectedMembers.compactMap(\.validationResult)).map(\.description).sorted()) to extension"
      )
    }

    var updatedDeclGroup = declGroup
    let remainingMembers = Array(declGroup.memberBlock.members).filter { !membersToMove.contains($0) }
    membersToMove[0].decl.leadingTrivia = membersToMove[0].decl.leadingTrivia.trimmingPrefix(while: \.isSpaceOrTab)
    
    updatedDeclGroup.memberBlock.members = MemberBlockItemListSyntax(remainingMembers)
    let extensionMemberBlockSyntax = declGroup.memberBlock.with(\.members, MemberBlockItemListSyntax(membersToMove))

    var declName = decl.name
    declName.trailingTrivia = declName.trailingTrivia.merging(.space)

    let extensionDecl = ExtensionDeclSyntax(
      leadingTrivia: .newlines(2),
      extendedType: IdentifierTypeSyntax(
        leadingTrivia: .space,
        name: declName
      ),
      memberBlock: extensionMemberBlockSyntax
    )

    var syntax = syntax
    let updatedStatement = statement.with(\.item, .decl(DeclSyntax(updatedDeclGroup)))
    syntax.statements[statementIndex] = updatedStatement
    syntax.statements.insert(
      CodeBlockItemSyntax(item: .decl(DeclSyntax(extensionDecl))),
      at: syntax.statements.index(after: statementIndex)
    )
    return syntax
  }
}

extension MoveMembersToExtension: SyntaxRefactoringCodeActionProvider {
  static var title: String { "Move to extension" }

  static func refactoringContext(for scope: SyntaxCodeActionScope) -> Context {
    Context(range: scope.range)
  }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> SourceFileSyntax? {
    scope.file
  }

  static func textRefactor(syntax: SourceFileSyntax, in context: Context) throws -> [SourceEdit] {

    let updatedSyntax = try self.refactor(syntax: syntax, in: context)

    return [
      .replace(syntax, with: updatedSyntax.description)
    ]
  }
}
