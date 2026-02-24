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

@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftIDEUtils
import SwiftParser
import SwiftSyntax

extension SwiftLanguageService {
  /// Builds semantic highlighting tokens for the given snapshot.
  ///
  /// Declaration names are always derived from the syntax tree, since SourceKit's semantic token
  /// response only covers usages/references and not declaration sites themselves. When a
  /// compile command is available, SourceKit reference tokens are merged on top so that they
  /// take precedence over the syntactically-derived declarations.
  private func semanticHighlightingTokens(for snapshot: DocumentSnapshot) async throws -> SyntaxHighlightingTokens {
    // Always produce declaration tokens from the syntax tree.
    let tree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let declarationVisitor = DeclarationHighlightingVisitor(snapshot: snapshot)
    declarationVisitor.walk(tree)
    var tokens = SyntaxHighlightingTokens(tokens: declarationVisitor.tokens)

    // Supplement with SourceKit reference tokens when we have a real compile command.
    guard let compileCommand = await self.compileCommand(for: snapshot.uri, fallbackAfterTimeout: false),
      !compileCommand.isFallback
    else {
      return tokens
    }

    let skreq = sourcekitd.dictionary([
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compileCommand.compilerArgs as [any SKDRequestValue],
    ])

    let dict = try await send(sourcekitdRequest: \.semanticTokens, skreq, snapshot: snapshot)

    guard let skTokens: SKDResponseArray = dict[keys.semanticTokens] else {
      return tokens
    }

    try Task.checkCancellation()

    let sourceKitTokens = SyntaxHighlightingTokenParser(sourcekitd: sourcekitd).parseTokens(skTokens, in: snapshot)
    // SourceKit reference tokens take precedence over our syntactically-derived declaration tokens.
    tokens = tokens.mergingTokens(with: sourceKitTokens)
    return tokens
  }

  /// Computes an array of syntax highlighting tokens from the syntax tree that
  /// have been merged with any semantic tokens from SourceKit. If the provided
  /// range is non-empty, this function restricts its output to only those
  /// tokens whose ranges overlap it. If no range is provided, tokens for the
  /// entire document are returned.
  ///
  /// - Parameter range: The range of tokens to restrict this function to, if any.
  /// - Returns: An array of syntax highlighting tokens.
  private func mergedAndSortedTokens(
    for snapshot: DocumentSnapshot,
    in range: Range<Position>? = nil
  ) async throws -> SyntaxHighlightingTokens {
    try Task.checkCancellation()

    async let tree = syntaxTreeManager.syntaxTree(for: snapshot)
    let semanticTokens = await orLog("Loading semantic tokens") { try await semanticHighlightingTokens(for: snapshot) }

    let byteRange =
      if let range {
        snapshot.byteSourceRange(of: range)
      } else {
        await tree.range
      }

    try Task.checkCancellation()

    let tokens =
      await tree
      .classifications(in: byteRange)
      .map { $0.highlightingTokens(in: snapshot) }
      .reduce(into: SyntaxHighlightingTokens(tokens: [])) { $0.tokens += $1.tokens }

    try Task.checkCancellation()

    let merged =
      tokens
      .mergingTokens(with: semanticTokens ?? SyntaxHighlightingTokens(tokens: []))
      .sorted { $0.start < $1.start }

    guard let range else { return merged }
    return SyntaxHighlightingTokens(tokens: merged.tokens.filter { range.overlaps($0.range) })
  }

  package func documentSemanticTokens(
    _ req: DocumentSemanticTokensRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    let snapshot = try await self.latestSnapshot(for: req.textDocument.uri)

    let tokens = try await mergedAndSortedTokens(for: snapshot)
    let encodedTokens = tokens.lspEncoded

    return DocumentSemanticTokensResponse(data: encodedTokens)
  }

  package func documentSemanticTokensDelta(
    _ req: DocumentSemanticTokensDeltaRequest
  ) async throws -> DocumentSemanticTokensDeltaResponse? {
    return nil
  }

  package func documentSemanticTokensRange(
    _ req: DocumentSemanticTokensRangeRequest
  ) async throws -> DocumentSemanticTokensResponse? {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)
    let tokens = try await mergedAndSortedTokens(for: snapshot, in: req.range)
    let encodedTokens = tokens.lspEncoded

    return DocumentSemanticTokensResponse(data: encodedTokens)
  }
}

extension SyntaxClassifiedRange {
  fileprivate func highlightingTokens(in snapshot: DocumentSnapshot) -> SyntaxHighlightingTokens {
    guard let (kind, modifiers) = self.kind.highlightingKindAndModifiers else {
      return SyntaxHighlightingTokens(tokens: [])
    }

    let multiLineRange = snapshot.absolutePositionRange(of: self.range)
    let ranges = multiLineRange.splitToSingleLineRanges(in: snapshot)

    let tokens = ranges.map {
      SyntaxHighlightingToken(
        range: $0,
        kind: kind,
        modifiers: modifiers
      )
    }

    return SyntaxHighlightingTokens(tokens: tokens)
  }
}

extension SyntaxClassification {
  fileprivate var highlightingKindAndModifiers: (SemanticTokenTypes, SemanticTokenModifiers)? {
    switch self {
    case .none:
      return nil
    case .editorPlaceholder:
      return nil
    case .keyword:
      return (.keyword, [])
    case .identifier, .type, .dollarIdentifier:
      return (.identifier, [])
    case .operator:
      return (.operator, [])
    case .integerLiteral, .floatLiteral:
      return (.number, [])
    case .stringLiteral:
      return (.string, [])
    case .regexLiteral:
      return (.regexp, [])
    case .ifConfigDirective:
      return (.macro, [])
    case .attribute:
      return (.modifier, [])
    case .lineComment, .blockComment:
      return (.comment, [])
    case .docLineComment, .docBlockComment:
      return (.comment, .documentation)
    case .argumentLabel:
      return (.function, .parameterLabel)
    #if RESILIENT_LIBRARIES
    @unknown default:
      fatalError("Unknown case")
    #endif
    }
  }
}

// MARK: - Declaration Highlighting

extension SwiftLanguageService {
  /// A `SyntaxVisitor` that emits semantic highlighting tokens for declaration name tokens.
  ///
  /// SourceKit's `source.request.semantic_tokens` response covers symbol *usages* but omits the
  /// declaration sites themselves. This visitor walks the AST and emits properly-typed tokens
  /// (e.g. `.variable`, `.property`, `.struct`) with the `.declaration` modifier for every named
  /// declaration so that editors can highlight them distinctly from plain identifiers.
  private final class DeclarationHighlightingVisitor: SyntaxVisitor {
    var tokens: [SyntaxHighlightingToken] = []
    private let snapshot: DocumentSnapshot

    /// Tracks the innermost scope kind so we can distinguish instance properties (`.property`)
    /// from local or global variables (`.variable`).
    private enum ScopeKind {
      case typeBody  // inside a struct / class / enum / actor / protocol member block
      case codeBody  // inside a function, initializer, or closure
    }
    private var scopeStack: [ScopeKind] = []
    private var isInTypeMemberScope: Bool { scopeStack.last == .typeBody }

    init(snapshot: DocumentSnapshot) {
      self.snapshot = snapshot
      super.init(viewMode: .sourceAccurate)
    }

    private func emit(_ token: TokenSyntax, kind: SemanticTokenTypes, modifiers: SemanticTokenModifiers) {
      let range = token.trimmedRange
      guard !range.isEmpty else { return }
      let lspRange = snapshot.absolutePositionRange(of: range)
      tokens += lspRange.splitToSingleLineRanges(in: snapshot).map {
        SyntaxHighlightingToken(range: $0, kind: kind, modifiers: modifiers)
      }
    }

    // MARK: Type declarations

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .struct, modifiers: [.declaration])
      scopeStack.append(.typeBody)
      return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { scopeStack.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .class, modifiers: [.declaration])
      scopeStack.append(.typeBody)
      return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { scopeStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .enum, modifiers: [.declaration])
      scopeStack.append(.typeBody)
      return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { scopeStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .actor, modifiers: [.declaration])
      scopeStack.append(.typeBody)
      return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { scopeStack.removeLast() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .interface, modifiers: [.declaration])
      scopeStack.append(.typeBody)
      return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { scopeStack.removeLast() }

    // MARK: Type aliases and associated types

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .typeParameter, modifiers: [.declaration])
      return .visitChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .typeParameter, modifiers: [.declaration])
      return .visitChildren
    }

    // MARK: Function and method declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
      var modifiers: SemanticTokenModifiers = [.declaration]
      if node.modifiers.contains(where: {
        $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
      }) {
        modifiers.insert(.static)
      }
      emit(node.name, kind: isInTypeMemberScope ? .method : .function, modifiers: modifiers)
      scopeStack.append(.codeBody)
      return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) { scopeStack.removeLast() }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
      // `init` is already classified as a keyword syntactically; push codeBody for the body scope.
      scopeStack.append(.codeBody)
      return .visitChildren
    }
    override func visitPost(_ node: InitializerDeclSyntax) { scopeStack.removeLast() }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
      scopeStack.append(.codeBody)
      return .visitChildren
    }
    override func visitPost(_ node: ClosureExprSyntax) { scopeStack.removeLast() }

    // MARK: Variable and property declarations

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
      guard let idPattern = node.pattern.as(IdentifierPatternSyntax.self) else {
        return .visitChildren
      }
      var modifiers: SemanticTokenModifiers = [.declaration]
      if let varDecl = node.parent?.parent?.as(VariableDeclSyntax.self),
        varDecl.modifiers.contains(where: {
          $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        })
      {
        modifiers.insert(.static)
      }
      emit(idPattern.identifier, kind: isInTypeMemberScope ? .property : .variable, modifiers: modifiers)
      return .visitChildren
    }

    // MARK: Optional binding conditions (if let x = ..., guard let x = ...)

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
      if let idPattern = node.pattern.as(IdentifierPatternSyntax.self) {
        emit(idPattern.identifier, kind: .variable, modifiers: [.declaration])
      }
      return .visitChildren
    }

    // MARK: Enum case declarations

    override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .enumMember, modifiers: [.declaration])
      return .visitChildren
    }

    // MARK: Macro declarations

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .macro, modifiers: [.declaration])
      return .visitChildren
    }
  }
}
