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
import SwiftBasicFormat
import SwiftRefactor
package import SwiftSyntax

package struct MoveMembersToExtension: SyntaxRefactoringProvider {
  package struct Context {
    let range: Range<AbsolutePosition>

    package init(range: Range<AbsolutePosition>) {
      self.range = range
    }
  }

  package static func refactor(syntax: SourceFileSyntax, in context: Context) throws -> SourceFileSyntax {
    let sourceDecl = try findSourceDecl(syntax: syntax, range: context.range)
    let selectedMembers = findSelectedMembers(declGroup: sourceDecl.declGroup, range: context.range)
    let membersToMove = try validateMovableMembers(selectedMembers: selectedMembers)
    let remainingMembers = updateRemainingMembers(declGroup: sourceDecl.declGroup, membersToMove: membersToMove)

    var updatedDeclGroup = sourceDecl.declGroup
    updatedDeclGroup.memberBlock = updateMemberBlock(
      sourceDecl.declGroup.memberBlock,
      members: remainingMembers
    )

    let extensionDecl = makeExtension(sourceDecl: sourceDecl, membersToMove: membersToMove)

    return updateSyntax(
      syntax,
      sourceDecl: sourceDecl,
      updatedDeclGroup: updatedDeclGroup,
      extensionDecl: extensionDecl
    )
  }
}

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
      } else {
        return nil
      }
    }
  }
}

private extension MoveMembersToExtension {
  struct MemberToMove {
    struct NestedMember: Equatable {
      let updatedMember: MemberBlockItemSyntax
      let partsToMove: [MemberBlockItemSyntax]
      let validationResults: [ValidationResult]
      let path: [String]
      let indentationToRemove: Trivia
    }

    enum Scope: Equatable {
      case inner
      case nested(NestedMember)
    }

    let member: MemberBlockItemSyntax
    let scope: Scope

    var validationResults: [ValidationResult] {
      switch scope {
      case .inner:
        return [ValidationResult(member)].compactMap { $0 }

      case .nested(let nested):
        return nested.validationResults
      }
    }

    var hasMovableMembers: Bool {
      switch scope {
      case .inner:
        return ValidationResult(member) == nil

      case .nested(let nested):
        return !nested.partsToMove.isEmpty
      }
    }

    init(
      member: MemberBlockItemSyntax,
      scope: Scope = .inner
    ) {
      self.member = member
      self.scope = scope
    }
  }

  struct SourceDecl {
    let statement: CodeBlockItemSyntax
    let index: CodeBlockItemListSyntax.Index
    let declGroup: any DeclGroupSyntax
    let declName: TokenSyntax
  }

  static func findSourceDecl(syntax: SourceFileSyntax, range: Range<AbsolutePosition>) throws -> SourceDecl {
    guard
      let statement = syntax.statements.first(where: { $0.item.range.contains(range) }),
      let decl = statement.item.asProtocol((any NamedDeclSyntax).self),
      let declGroup = statement.item.asProtocol((any DeclGroupSyntax).self),
      let index = syntax.statements.index(of: statement)
    else {
      throw RefactoringNotApplicableError("Type declaration not found")
    }

    return SourceDecl(statement: statement, index: index, declGroup: declGroup, declName: decl.name)
  }

  static func findSelectedMembers(declGroup: any DeclGroupSyntax, range: Range<AbsolutePosition>) -> [MemberToMove] {
    declGroup.memberBlock.members.compactMap { member in
      guard range.overlaps(member.trimmedRange) else { return nil }

      if let nestedMember = findNestedMovableMember(member: member, range: range) {
        return MemberToMove(
          member: member,
          scope: .nested(nestedMember)
        )
      }

      return MemberToMove(member: member)
    }
  }

  static func validateMovableMembers(selectedMembers: [MemberToMove]) throws -> [MemberToMove] {
    let membersToMove = selectedMembers.filter(\.hasMovableMembers)

    guard !membersToMove.isEmpty else {
      let notMovedMembers = Set(selectedMembers.flatMap(\.validationResults))
        .map(\.description)
        .sorted().joined(separator: ", ")
      throw RefactoringNotApplicableError(
        "Cannot move \(notMovedMembers) to extension"
      )
    }

    return membersToMove
  }

  static func updateRemainingMembers(
    declGroup: any DeclGroupSyntax,
    membersToMove: [MemberToMove]
  ) -> [MemberBlockItemSyntax] {

    let wholeMembers = membersToMove.compactMap { move in
      if case .inner = move.scope {
        return move.member
      }
      return nil
    }

    var remainingMembers = Array(declGroup.memberBlock.members).filter { !wholeMembers.contains($0) }

    for index in remainingMembers.indices {
      guard let move = membersToMove.first(where: { $0.member == remainingMembers[index] }),
        case .nested(let nested) = move.scope
      else {
        continue
      }

      remainingMembers[index] = nested.updatedMember
    }

    return remainingMembers
  }

  static func updateMemberBlock(
    _ memberBlock: MemberBlockSyntax,
    members: [MemberBlockItemSyntax]
  ) -> MemberBlockSyntax {
    var memberBlock = memberBlock
    var members = members

    if members.isEmpty {
      memberBlock.members = MemberBlockItemListSyntax()
      memberBlock.rightBrace.leadingTrivia = Trivia()
      return memberBlock
    }

    members[0].leadingTrivia = .newline.merging(
      members[0]
        .leadingTrivia
        .trimmingPrefix(while: \.isNewline)
    )

    let lastIndex = members.index(before: members.endIndex)

    members[lastIndex].trailingTrivia =
      members[lastIndex]
      .trailingTrivia
      .trimmingSuffix(while: \.isNewline)

    memberBlock.members = MemberBlockItemListSyntax(members)
    return memberBlock
  }

  static func findNestedMovableMember(
    member: MemberBlockItemSyntax,
    range: Range<AbsolutePosition>
  ) -> MemberToMove.NestedMember? {
    guard let memberGroup = member.decl.asProtocol((any DeclGroupSyntax).self),
      let memberName = member.decl.asProtocol((any NamedDeclSyntax).self)?.name.text
    else {
      return nil
    }

    var currentGroup = memberGroup
    var path = [memberName]
    var declGroups = [(declGroup: any DeclGroupSyntax, index: Int)]()

    while true {
      let members = Array(currentGroup.memberBlock.members)

      let selectedIndices = members.indices.filter { range.overlaps(members[$0].trimmedRange) }

      guard selectedIndices.count == 1,
        let selectedIndex = selectedIndices.first,
        let childGroup = members[selectedIndex].decl.asProtocol((any DeclGroupSyntax).self),
        let childName = members[selectedIndex].decl.asProtocol((any NamedDeclSyntax).self)?.name.text,
        childGroup.memberBlock.members.contains(where: { range.overlaps($0.trimmedRange) })
      else {
        break
      }

      declGroups.append((currentGroup, selectedIndex))

      currentGroup = childGroup
      path.append(childName)
    }

    let selectedMembers = Array(currentGroup.memberBlock.members).filter { range.overlaps($0.trimmedRange) }

    guard !selectedMembers.isEmpty else { return nil }

    let partsToMove = selectedMembers.filter { ValidationResult($0) == nil }

    let validationResults = selectedMembers.compactMap(ValidationResult.init)

    let remainingMembers = selectedMembers.filter { !partsToMove.contains($0) }

    var updatedGroup = currentGroup
    updatedGroup.memberBlock = updateMemberBlock(currentGroup.memberBlock, members: remainingMembers)

    for (declGroup, index) in declGroups.reversed() {
      var parentMembers = Array(declGroup.memberBlock.members)

      parentMembers[index].decl = DeclSyntax(updatedGroup)

      var updatedParent = declGroup
      updatedParent.memberBlock.members = MemberBlockItemListSyntax(parentMembers)
      updatedGroup = updatedParent
    }

    var updatedMember = member
    updatedMember.decl = DeclSyntax(updatedGroup)

    let indentationToRemove =
      currentGroup
      .firstToken(viewMode: .sourceAccurate)?
      .indentationOfLine
      ?? Trivia()

    return MemberToMove.NestedMember(
      updatedMember: updatedMember,
      partsToMove: partsToMove,
      validationResults: validationResults,
      path: path,
      indentationToRemove: indentationToRemove
    )
  }

  static func unindentExtensionMembers(
    _ members: [MemberBlockItemSyntax],
    by indentation: Trivia
  ) -> [MemberBlockItemSyntax] {
    members.map { member in
      let remover = IndentationRemover(
        indentation: indentation,
        indentFirstLine: true
      )

      return
        remover
        .rewrite(member)
        .as(MemberBlockItemSyntax.self)
        ?? member
    }
  }

  static func makeExtensionName(
    rootName: TokenSyntax,
    path: [String]
  ) -> TypeSyntax {
    var rootName = rootName
    rootName.leadingTrivia = Trivia()
    rootName.trailingTrivia = Trivia()

    var type = TypeSyntax(
      IdentifierTypeSyntax(
        leadingTrivia: .space,
        name: rootName
      )
    )

    for component in path {
      type = TypeSyntax(
        MemberTypeSyntax(
          baseType: type,
          period: .periodToken(),
          name: .identifier(component)
        )
      )
    }

    type.trailingTrivia = .space
    return type
  }

  static func makeExtension(sourceDecl: SourceDecl, membersToMove: [MemberToMove]) -> ExtensionDeclSyntax {
    var extensionMembers = [MemberBlockItemSyntax]()
    var declName = sourceDecl.declName
    declName.trailingTrivia = declName.trailingTrivia.merging(.space)

    let extendedType: TypeSyntax

    if membersToMove.count == 1,
      case .nested(let nested) = membersToMove[0].scope
    {
      extensionMembers = unindentExtensionMembers(
        nested.partsToMove,
        by: nested.indentationToRemove
      )

      extendedType = makeExtensionName(
        rootName: sourceDecl.declName,
        path: nested.path
      )
    } else {
      extensionMembers = membersToMove.map(\.member)

      extendedType = makeExtensionName(
        rootName: sourceDecl.declName,
        path: []
      )
    }

    extensionMembers[0].leadingTrivia = .newline.merging(
      extensionMembers[0].leadingTrivia.trimmingPrefix(while: \.isNewline)
    )

    var memberBlock = sourceDecl.declGroup.memberBlock
    memberBlock.members = MemberBlockItemListSyntax(extensionMembers)

    return ExtensionDeclSyntax(
      leadingTrivia: .newlines(2),
      extendedType: extendedType,
      memberBlock: memberBlock
    )
  }

  static func updateSyntax(
    _ syntax: SourceFileSyntax,
    sourceDecl: SourceDecl,
    updatedDeclGroup: any DeclGroupSyntax,
    extensionDecl: ExtensionDeclSyntax
  ) -> SourceFileSyntax {
    var syntax = syntax
    syntax.statements[sourceDecl.index] = sourceDecl.statement.with(\.item, .decl(DeclSyntax(updatedDeclGroup)))
    syntax.statements.insert(
      CodeBlockItemSyntax(item: .decl(DeclSyntax(extensionDecl))),
      at: syntax.statements.index(after: sourceDecl.index)
    )
    return syntax
  }
}

extension MoveMembersToExtension: ResolvableSyntaxRefactoringCodeActionProvider {
  static func refactoringContext(
    for node: SwiftSyntax.SourceFileSyntax,
    in scope: SyntaxCodeActionScope
  ) -> RefactoringContext<Context, EmptyLSPCodable> {
    .context(Context(range: scope.range))
  }

  static func resolveContext(
    for data: UnresolvedData,
    in scope: SyntaxCodeActionScope,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> Context {
    Context(range: scope.range)
  }

  typealias UnresolvedData = EmptyLSPCodable

  static var title: String { "Move to extension" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> SourceFileSyntax? {
    guard scope.range.lowerBound != scope.range.upperBound else {
      return nil
    }

    return scope.file
  }
}

fileprivate extension Trivia {
  func trimmingPrefix(
    while predicate: (TriviaPiece) -> Bool
  ) -> Trivia {
    Trivia(pieces: self.drop(while: predicate))
  }

  func trimmingSuffix(
    while predicate: (TriviaPiece) -> Bool
  ) -> Trivia {
    Trivia(
      pieces: self[...]
        .reversed()
        .drop(while: predicate)
        .reversed()
    )
  }
}
