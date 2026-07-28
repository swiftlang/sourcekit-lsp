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
import SwiftRefactor
package import SwiftSyntax

enum RefactoringContext<Context, UnresolvedData: LSPAnyCodable> {
  case context(Context)
  case unresolved(UnresolvedData)
}

/// Protocol that adapts a `SyntaxRefactoringProvider` (which comes from swift-syntax) into a `SyntaxCodeActionProvider`, allowing asynchronous
/// resolving of semantic properties.
///
/// `SyntaxRefactoringCodeActionProvider` is a specialized version of this protocol for code actions that can syntactically generate the post-edit
/// test during the `textDocument/codeAction` request and don't need to resolve any semantic information.
protocol ResolvableSyntaxRefactoringCodeActionProvider: SyntaxCodeActionProvider, EditRefactoringProvider {
  static var title: String { get }

  /// Returns the node that the syntax refactoring should be performed on, if code actions are requested for the given
  /// scope.
  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input?

  associatedtype UnresolvedData: LSPAnyCodable

  /// The refactoring context with which to run the `SyntaxRefactoringProvider`.
  ///
  /// If this returns a refactoring context, the refactoring's edits are computed and returned from the `textDocument/codeAction` request.
  /// If `UnresolvedData` is returned, no edit is computed. The client is expected to call `codeAction/resolve` to resolve the edit. `resolveContext`
  /// will be called in that case to resolve the context.
  static func refactoringContext(
    for node: Input,
    in scope: SyntaxCodeActionScope
  ) -> RefactoringContext<Context, UnresolvedData>

  /// Resolve the refactoring's context during a `codeAction/resolve` request.
  ///
  /// May call `symbolInfo` to retrieve semantic information about the current document.
  static func resolveContext(
    for data: UnresolvedData,
    in scope: SyntaxCodeActionScope,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> Context
}

/// SyntaxCodeActionProviders with a \c Void context can automatically be
/// adapted provide a code action based on their refactoring operation.
extension ResolvableSyntaxRefactoringCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = nodeToRefactor(in: scope) else {
      return []
    }

    let context: Context
    switch refactoringContext(for: node, in: scope) {
    case .context(let c):
      context = c
    case .unresolved(let data):
      return [
        CodeAction(
          title: Self.title,
          kind: .refactorInline,
          data: UnresolvedCodeActionData(
            actionType: Self.self,
            document: VersionedTextDocumentIdentifier(scope.snapshot.uri, version: scope.snapshot.version),
            range: scope.requestedRange,
            data: data.encodeToLSPAny()
          ).encodeToLSPAny()
        )
      ]
    }
    guard let sourceEdits = try? Self.textRefactor(syntax: node, in: context) else {
      return []
    }

    guard let workspaceEdit = sourceEdits.asWorkspaceEdit(snapshot: scope.snapshot) else {
      return []
    }

    return [
      CodeAction(
        title: Self.title,
        kind: .refactorInline,
        edit: workspaceEdit
      )
    ]
  }

  package static func resolve(
    _ codeAction: CodeAction,
    in scope: SyntaxCodeActionScope,
    unresolvedData: LSPAny,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> CodeAction {
    guard let node = nodeToRefactor(in: scope) else {
      throw ResponseError.internalError("Unable to find node to refactor")
    }
    guard let unresolvedData = UnresolvedData(fromLSPAny: unresolvedData) else {
      throw ResponseError.internalError("Unable to parse the unresolved data")
    }

    let context = try await resolveContext(
      for: unresolvedData,
      in: scope,
      symbolInfo: symbolInfo
    )
    let sourceEdits = try Self.textRefactor(syntax: node, in: context)

    // `asWorkspaceEdit` returning `nil` signifies that no edits need to be performed. Since the user has already
    // selected this action, we cannot filter it out anymore. Simply return the empty edits.
    let workspaceEdit = sourceEdits.asWorkspaceEdit(snapshot: scope.snapshot) ?? WorkspaceEdit()

    return CodeAction(
      title: Self.title,
      kind: .refactorInline,
      edit: workspaceEdit
    )
  }
}

package struct EmptyLSPCodable: Codable, LSPAnyCodable {}

protocol SyntaxRefactoringCodeActionProvider: ResolvableSyntaxRefactoringCodeActionProvider
where Context == Void, UnresolvedData == EmptyLSPCodable {}

extension SyntaxRefactoringCodeActionProvider {
  static func refactoringContext(
    for node: Input,
    in scope: SyntaxCodeActionScope
  ) -> RefactoringContext<Context, EmptyLSPCodable> {
    return .context(())
  }

  static func resolveContext(
    for data: EmptyLSPCodable,
    in scope: SyntaxCodeActionScope,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> Context {
    throw ResponseError.internalError("\(Self.self) should always return text edits and never need to be resolved")
  }
}

// MARK: Utilities

extension SyntaxProtocol {
  /// Finds the innermost parent of the given type that satisfies `matching`,
  /// while not walking outside of nodes that satisfy `stoppingIf`.
  package func findParentOfSelf<ParentType: SyntaxProtocol>(
    ofType: ParentType.Type,
    stoppingIf: (Syntax) -> Bool,
    matching: (ParentType) -> Bool = { _ in true }
  ) -> ParentType? {
    var node: Syntax? = Syntax(self)
    while let unwrappedNode = node, !stoppingIf(unwrappedNode) {
      if let expectedType = unwrappedNode.as(ParentType.self), matching(expectedType) {
        return expectedType
      }
      node = unwrappedNode.parent
    }
    return nil
  }
}

extension [SourceEdit] {
  /// Translate source edits into a workspace edit.
  /// `snapshot` is the latest snapshot of the document to which these edits belong.
  func asWorkspaceEdit(snapshot: DocumentSnapshot) -> WorkspaceEdit? {
    let textEdits = compactMap { edit -> TextEdit? in
      let edit = TextEdit(
        range: snapshot.positionRange(of: edit.range),
        newText: edit.replacement
      )

      if edit.isNoOp(in: snapshot) {
        return nil
      }

      return edit
    }

    if textEdits.isEmpty {
      return nil
    }

    return WorkspaceEdit(
      changes: [snapshot.uri: textEdits]
    )
  }
}

// MARK: - Helper Extensions

extension TypeSyntax {
  var isVoid: Bool {
    switch self.as(TypeSyntaxEnum.self) {
    case .identifierType(let identifierType) where identifierType.name.text == "Void":
      return true
    case .tupleType(let tupleType) where tupleType.elements.isEmpty:
      return true
    default:
      return false
    }
  }
}

extension TokenSyntax {
  var trivia: Trivia {
    return leadingTrivia + trailingTrivia
  }
}

extension Trivia {
  var droppingLeadingWhitespace: Trivia {
    return Trivia(pieces: self.drop(while: \.isWhitespace))
  }

  var droppingTrailingWhitespace: Trivia {
    return Trivia(pieces: self.reversed().drop(while: \.isWhitespace).reversed())
  }
}

// MARK: Adapters for specific refactoring provides in swift-syntax.

extension AddSeparatorsToIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Add digit separators" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IntegerLiteralExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension ConvertComputedPropertyToStored: SyntaxRefactoringCodeActionProvider {
  static var title: String { "Convert to stored property" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> VariableDeclSyntax? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: VariableDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) || $0.is(AccessorBlockSyntax.self) }
    )
  }
}

extension ConvertComputedPropertyToZeroParameterFunction: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Convert to zero parameter function" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: VariableDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) || $0.is(AccessorBlockSyntax.self) }
    )
  }
}

extension FormatRawStringLiteral: SyntaxRefactoringCodeActionProvider {
  package static var title: String {
    "Convert string literal to minimal number of '#'s"
  }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: StringLiteralExprSyntax.self,
      stoppingIf: {
        $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self)
          || $0.keyPathInParent == \ExpressionSegmentSyntax.expressions
      }
    )
  }
}

extension MigrateToNewIfLetSyntax: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Migrate to shorthand 'if let' syntax" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IfExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension OpaqueParameterToGeneric: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Expand 'some' parameters to generic parameters" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: DeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension RemoveSeparatorsFromIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Remove digit separators" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IntegerLiteralExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension RemoveRedundantParentheses: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Remove Redundant Parentheses" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: TupleExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension ConvertZeroParameterFunctionToComputedProperty: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Convert to computed property" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    let functionDecl = scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: FunctionDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
    guard let functionDecl, !(functionDecl.signature.returnClause?.type.isVoid ?? true) else {
      return nil
    }
    return functionDecl
  }
}

//==========================================================================//
// IMPORTANT: If you are tempted to add a new refactoring action here       //
// please insert it in alphabetical order above                             //
//==========================================================================//
