//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SwiftRefactor
import SwiftSyntax

/// Protocol that adapts a SyntaxRefactoringProvider (that comes from
/// swift-syntax) into a SyntaxCodeActionProvider.
protocol SyntaxRefactoringCodeActionProvider: SyntaxCodeActionProvider, EditRefactoringProvider {
  static var title: String { get }

  /// Returns the node that the syntax refactoring should be performed on, if code actions are requested for the given
  /// scope.
  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input?
}

/// SyntaxCodeActionProviders with a \c Void context can automatically be
/// adapted provide a code action based on their refactoring operation.
extension SyntaxRefactoringCodeActionProvider where Self.Context == Void {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let node = nodeToRefactor(in: scope) else {
      return []
    }

    let sourceEdits = Self.textRefactor(syntax: node)

    let textEdits = sourceEdits.compactMap { (edit) -> TextEdit? in
      let edit = TextEdit(
        range: scope.snapshot.absolutePositionRange(of: edit.range),
        newText: edit.replacement
      )
      if edit.isNoOp(in: scope.snapshot) {
        return nil
      }
      return edit
    }

    if textEdits.isEmpty {
      return []
    }

    return [
      CodeAction(
        title: Self.title,
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: textEdits])
      )
    ]
  }
}

// Adapters for specific refactoring provides in swift-syntax.

extension AddSeparatorsToIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Add digit separators" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IntegerLiteralExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension FormatRawStringLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String {
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
  public static var title: String { "Migrate to shorthand 'if let' syntax" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IfExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension OpaqueParameterToGeneric: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Expand 'some' parameters to generic parameters" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: DeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension RemoveSeparatorsFromIntegerLiteral: SyntaxRefactoringCodeActionProvider {
  public static var title: String { "Remove digit separators" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IntegerLiteralExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension ConvertZeroParameterFunctionToComputedProperty: SyntaxRefactoringCodeActionProvider {
  static var title: String { "Convert to computed property" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: FunctionDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension ConvertComputedPropertyToZeroParameterFunction: SyntaxRefactoringCodeActionProvider {
  static var title: String { "Convert to zero parameter function" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: VariableDeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
  }
}

extension SyntaxProtocol {
  /// Finds the innermost parent of the given type while not walking outside of nodes that satisfy `stoppingIf`.
  func findParentOfSelf<ParentType: SyntaxProtocol>(
    ofType: ParentType.Type,
    stoppingIf: (Syntax) -> Bool
  ) -> ParentType? {
    var node: Syntax? = Syntax(self)
    while let unwrappedNode = node, !stoppingIf(unwrappedNode) {
      if let expectedType = unwrappedNode.as(ParentType.self) {
        return expectedType
      }
      node = unwrappedNode.parent
    }
    return nil
  }
}
