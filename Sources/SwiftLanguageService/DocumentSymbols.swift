//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitLSP
import SwiftSyntax

extension SwiftLanguageService {
  package func documentSymbol(_ req: DocumentSymbolRequest) async throws -> DocumentSymbolResponse? {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    try Task.checkCancellation()
    return .documentSymbols(
      DocumentSymbolsFinder.find(
        in: [Syntax(syntaxTree)],
        snapshot: snapshot,
        range: syntaxTree.position..<syntaxTree.endPosition
      )
    )
  }
}

// MARK: - DocumentSymbolsFinder

private final class DocumentSymbolsFinder: SyntaxAnyVisitor {
  /// The snapshot of the document for which we are getting document symbols.
  private let snapshot: DocumentSnapshot

  /// Only document symbols that intersect with this range get reported.
  private let range: Range<AbsolutePosition>

  /// Accumulating the result in here.
  private var result: [DocumentSymbol] = []

  private init(snapshot: DocumentSnapshot, range: Range<AbsolutePosition>) {
    self.snapshot = snapshot
    self.range = range
    super.init(viewMode: .sourceAccurate)
  }

  /// Designated entry point for `DocumentSymbolFinder`.
  static func find(
    in nodes: some Sequence<Syntax>,
    snapshot: DocumentSnapshot,
    range: Range<AbsolutePosition>
  ) -> [DocumentSymbol] {
    let visitor = DocumentSymbolsFinder(snapshot: snapshot, range: range)
    for node in nodes {
      visitor.walk(node)
    }
    return visitor.result
  }

  /// Add a symbol with the given parameters to the `result` array.
  private func record(
    node: some SyntaxProtocol,
    name: String,
    symbolKind: SymbolKind,
    range: Range<AbsolutePosition>,
    selection: Range<AbsolutePosition>
  ) -> SyntaxVisitorContinueKind {
    if !self.range.overlaps(range) {
      return .skipChildren
    }
    let positionRange = snapshot.absolutePositionRange(of: range)
    let selectionPositionRange = snapshot.absolutePositionRange(of: selection)

    // Record MARK comments on the node's leading and trailing trivia in `result` not as a child of `node`.
    visit(node.leadingTrivia, position: node.position)

    let children = DocumentSymbolsFinder.find(
      in: node.children(viewMode: .sourceAccurate),
      snapshot: snapshot,
      range: node.positionAfterSkippingLeadingTrivia..<node.endPositionBeforeTrailingTrivia
    )
    result.append(
      DocumentSymbol(
        name: name,
        kind: symbolKind,
        range: positionRange,
        selectionRange: selectionPositionRange,
        children: children
      )
    )
    visit(node.trailingTrivia, position: node.endPositionBeforeTrailingTrivia)
    return .skipChildren
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    guard let node = node.asProtocol((any NamedDeclSyntax).self) else {
      return .visitChildren
    }
    let symbolKind: SymbolKind? =
      switch node.kind {
      case .actorDecl: .class
      case .associatedTypeDecl: .typeParameter
      case .classDecl: .class
      case .enumDecl: .enum
      case .macroDecl: .function  // LSP doesn't have a macro symbol kind. `function`` is closest.
      case .operatorDecl: .operator
      case .precedenceGroupDecl: .operator  // LSP doesn't have a precedence group symbol kind. `operator` is closest.
      case .protocolDecl: .interface
      case .structDecl: .struct
      case .typeAliasDecl: .typeParameter  // LSP doesn't have a typealias symbol kind. `typeParameter` is closest.
      default: nil
      }

    guard let symbolKind else {
      return .visitChildren
    }
    return record(
      node: node,
      name: node.name.text,
      symbolKind: symbolKind,
      range: node.rangeWithoutTrivia,
      selection: node.name.rangeWithoutTrivia
    )
  }

  private func visit(_ trivia: Trivia, position: AbsolutePosition) {
    let markPrefix = "MARK: "
    var position = position
    for piece in trivia.pieces {
      defer {
        position = position.advanced(by: piece.sourceLength.utf8Length)
      }
      switch piece {
      case .lineComment(let commentText), .blockComment(let commentText):
        let trimmedComment = commentText.trimmingCharacters(in: CharacterSet(["/", "*"]).union(.whitespaces))
        if trimmedComment.starts(with: markPrefix) {
          let markText = trimmedComment.dropFirst(markPrefix.count)
          let range = snapshot.absolutePositionRange(
            of: position..<position.advanced(by: piece.sourceLength.utf8Length)
          )
          result.append(
            DocumentSymbol(
              name: String(markText),
              kind: .namespace,
              range: range,
              selectionRange: range,
              children: nil
            )
          )
        }
      default:
        break
      }
    }
  }

  override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
    if self.range.overlaps(node.position..<node.positionAfterSkippingLeadingTrivia) {
      self.visit(node.leadingTrivia, position: node.position)
    }
    if range.overlaps(node.endPositionBeforeTrailingTrivia..<node.endPosition) {
      self.visit(node.trailingTrivia, position: node.endPositionBeforeTrailingTrivia)
    }
    return .skipChildren
  }

  override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    // LSP doesn't have a destructor kind. constructor is the closest match and also what clangd for destructors.
    return record(
      node: node,
      name: node.deinitKeyword.text,
      symbolKind: .constructor,
      range: node.rangeWithoutTrivia,
      selection: node.deinitKeyword.rangeWithoutTrivia
    )
  }

  override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
    let rangeEnd =
      if let parameterClause = node.parameterClause {
        parameterClause.endPositionBeforeTrailingTrivia
      } else {
        node.name.endPositionBeforeTrailingTrivia
      }

    return record(
      node: node,
      name: node.declName,
      symbolKind: .enumMember,
      range: node.name.positionAfterSkippingLeadingTrivia..<rangeEnd,
      selection: node.name.positionAfterSkippingLeadingTrivia..<rangeEnd
    )
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    return record(
      node: node,
      name: node.extendedType.trimmedDescription,
      symbolKind: .namespace,
      range: node.rangeWithoutTrivia,
      selection: node.extendedType.rangeWithoutTrivia
    )
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    let kind: SymbolKind =
      if node.name.tokenKind.isOperator {
        .operator
      } else if node.parent?.is(MemberBlockItemSyntax.self) ?? false {
        .method
      } else {
        .function
      }
    return record(
      node: node,
      name: node.declName,
      symbolKind: kind,
      range: node.rangeWithoutTrivia,
      selection: node.name
        .positionAfterSkippingLeadingTrivia..<node.signature.parameterClause.endPositionBeforeTrailingTrivia
    )
  }

  override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind {
    return record(
      node: node,
      name: node.name.text,
      symbolKind: .typeParameter,
      range: node.rangeWithoutTrivia,
      selection: node.rangeWithoutTrivia
    )
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    return record(
      node: node,
      name: node.declName,
      symbolKind: .constructor,
      range: node.rangeWithoutTrivia,
      selection: node.initKeyword
        .positionAfterSkippingLeadingTrivia..<node.signature.parameterClause.endPositionBeforeTrailingTrivia
    )
  }

  override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
    // If there is only one pattern binding within the variable decl, consider the entire variable decl as the
    // referenced range. If there are multiple, consider each pattern binding separately since the `var` keyword doesn't
    // belong to any pattern binding in particular.
    guard let variableDecl = node.parent?.parent?.as(VariableDeclSyntax.self),
      variableDecl.isMemberOrTopLevelDeclaration
    else {
      return .visitChildren
    }
    let rangeNode: Syntax = variableDecl.bindings.count == 1 ? Syntax(variableDecl) : Syntax(node)

    return record(
      node: node,
      name: node.pattern.trimmedDescription,
      symbolKind: variableDecl.parent?.is(MemberBlockItemSyntax.self) ?? false ? .property : .variable,
      range: rangeNode.rangeWithoutTrivia,
      selection: node.pattern.rangeWithoutTrivia
    )
  }
}

// MARK: - Syntax Utilities

fileprivate extension EnumCaseElementSyntax {
  var declName: String {
    var result = self.name.text
    if let parameterClause {
      result += "("
      for parameter in parameterClause.parameters {
        result += "\(parameter.firstName?.text ?? "_"):"
      }
      result += ")"
    }
    return result
  }
}

fileprivate extension FunctionDeclSyntax {
  var declName: String {
    var result = self.name.text
    result += "("
    for parameter in self.signature.parameterClause.parameters {
      result += "\(parameter.firstName.text):"
    }
    result += ")"
    return result
  }
}

fileprivate extension InitializerDeclSyntax {
  var declName: String {
    var result = self.initKeyword.text
    result += "("
    for parameter in self.signature.parameterClause.parameters {
      result += "\(parameter.firstName.text):"
    }
    result += ")"
    return result
  }
}

fileprivate extension SyntaxProtocol {
  /// The position range of this node without its leading and trailing trivia.
  var rangeWithoutTrivia: Range<AbsolutePosition> {
    return positionAfterSkippingLeadingTrivia..<endPositionBeforeTrailingTrivia
  }

  /// Whether this is a top-level constant or a member of a type, ie. if this is not a local variable.
  var isMemberOrTopLevelDeclaration: Bool {
    if self.parent?.is(MemberBlockItemSyntax.self) ?? false {
      return true
    }
    if let codeBlockItem = self.parent?.as(CodeBlockItemSyntax.self),
      codeBlockItem.parent?.parent?.is(SourceFileSyntax.self) ?? false
    {
      return true
    }
    return false
  }
}

fileprivate extension TokenKind {
  var isOperator: Bool {
    switch self {
    case .prefixOperator, .binaryOperator, .postfixOperator: return true
    default: return false
    }
  }
}
