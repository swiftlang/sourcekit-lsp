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
@_spi(SourceKitLSP) import SKLogging
import SourceKitLSP
import SwiftRefactor
import SwiftSyntax

/// Data that is included in a `CodeAction` response for which the client should resolve the edit lazily using a `codeAction/resolve` request.
///
/// This data allows us to re-construct the `SyntaxCodeActionScope`.
struct UnresolvedCodeActionData: Codable, LSPAnyCodable {
  /// A string representation of the syntax refactoring action's type.
  let action: String

  /// The document on which the code action should be applied.
  let document: VersionedTextDocumentIdentifier

  /// The range at which the code action was originally requested.
  let range: Range<Position>

  init<Metatype: SyntaxRefactoringCodeActionProvider>(
    actionType: Metatype.Type,
    document: VersionedTextDocumentIdentifier,
    range: Range<Position>,
  ) {
    self.action = "\(Metatype.self)"
    self.document = document
    self.range = range
  }
}

enum SyntaxCodeActionContextResult<Context> {
  /// The cont
  case context(Context)
  /// Report a code action without the `edit` properties. The client is expected to send a `codeAction/resolve` request to resolve the edit.
  ///
  /// Must only be returned if the the client can resolve edits.
  case resolveEditLazily
}

/// Protocol that adapts a SyntaxRefactoringProvider (that comes from
/// swift-syntax) into a SyntaxCodeActionProvider.
protocol SyntaxRefactoringCodeActionProvider: SyntaxCodeActionProvider, EditRefactoringProvider {
  static var title: String { get }

  /// Returns the node that the syntax refactoring should be performed on, if code actions are requested for the given
  /// scope.
  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input?

  /// Retrieve the refactoring context to refactor the given node in the given scope.
  ///
  /// Throwing an error from this method causes the code action to be reported without any workspace edits. The client is expected to send a
  /// `codeAction/resolve` request when the user selects the code action in order to retrieve the semantic information and compute the actual edits.
  static func refactoringContext(
    for node: Input,
    in scope: SyntaxCodeActionScope
  ) async -> SyntaxCodeActionContextResult<Context>
}

extension SyntaxRefactoringCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) async -> [CodeAction] {
    guard let node = nodeToRefactor(in: scope) else {
      return []
    }

    let context: Context
    switch await refactoringContext(for: node, in: scope) {
    case .context(let c): context = c
    case .resolveEditLazily:
      guard scope.resolveSupport?.canResolveEdit ?? false else {
        logger.fault(
          "Refactoring action \(Self.self) requested lazy resolution of edits but client cannot resolve edits"
        )
        return []
      }
      return [
        CodeAction(
          title: Self.title,
          kind: .refactorInline,
          data: UnresolvedCodeActionData(
            actionType: Self.self,
            document: VersionedTextDocumentIdentifier(scope.snapshot.uri, version: scope.snapshot.version),
            range: scope.requestedRange
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
}

/// SyntaxCodeActionProviders with a `Void` context can automatically be adapted provide a code action based on their
/// refactoring operation.
extension SyntaxRefactoringCodeActionProvider where Context == Void {
  static func refactoringContext(
    for node: Input,
    in scope: SyntaxCodeActionScope
  ) -> SyntaxCodeActionContextResult<Context> {
    return .context(())
  }
}

// MARK: Utilities

extension SyntaxProtocol {
  /// Finds the innermost parent of the given type that satisfies `matching`,
  /// while not walking outside of nodes that satisfy `stoppingIf`.
  func findParentOfSelf<ParentType: SyntaxProtocol>(
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

private extension TypeSyntax {
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
