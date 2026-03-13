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
  /// Returns semantic reference tokens from SourceKit for the given snapshot, or `nil` if
  /// no real compile command is available or the request fails.
  private func sourceKitReferenceTokens(for snapshot: DocumentSnapshot) async throws -> SyntaxHighlightingTokens? {
    guard let compileCommand = await self.compileCommand(for: snapshot.uri, fallbackAfterTimeout: false),
      !compileCommand.isFallback
    else {
      return nil
    }

    let skreq = sourcekitd.dictionary([
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compileCommand.compilerArgs as [any SKDRequestValue],
    ])

    let dict = try await send(sourcekitdRequest: \.semanticTokens, skreq, snapshot: snapshot)

    guard let skTokens: SKDResponseArray = dict[keys.semanticTokens] else {
      return nil
    }

    try Task.checkCancellation()

    return SyntaxHighlightingTokenParser(sourcekitd: sourcekitd).parseTokens(skTokens, in: snapshot)
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

    let tree = await syntaxTreeManager.syntaxTree(for: snapshot)

    let byteRange =
      if let range {
        snapshot.byteSourceRange(of: range)
      } else {
        tree.range
      }

    try Task.checkCancellation()

    // Syntactic classification tokens (keywords, literals, comments, etc.)
    let syntaxTokens =
      tree
      .classifications(in: byteRange)
      .map { $0.highlightingTokens(in: snapshot) }
      .reduce(into: SyntaxHighlightingTokens(tokens: [])) { $0.tokens += $1.tokens }

    // Declaration name tokens derived from the syntax tree
    let declarationVisitor = DeclarationHighlightingVisitor(snapshot: snapshot)
    declarationVisitor.walk(tree)
    let declarationTokens = SyntaxHighlightingTokens(tokens: declarationVisitor.tokens)
    
    try Task.checkCancellation()

    let skTokens = await orLog("Loading SourceKit reference tokens") {
      try await sourceKitReferenceTokens(for: snapshot)
    }

    let merged =
      syntaxTokens
      .mergingTokens(with: declarationTokens)
      .mergingTokens(with: skTokens ?? SyntaxHighlightingTokens(tokens: []))
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

    /// Returns `true` if `node` is directly enclosed in a type body (struct, class, enum, actor,
    /// protocol, or extension member list) rather than a function or closure body.
    private func isInTypeMemberScope(_ node: some SyntaxProtocol) -> Bool {
      var current = node.parent
      while let parent = current {
        if parent.isProtocol((any DeclGroupSyntax).self) { return true }
        if parent.is(FunctionDeclSyntax.self) || parent.is(InitializerDeclSyntax.self)
            || parent.is(ClosureExprSyntax.self) { return false }
        current = parent.parent
      }
      return false
    }

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
      return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .class, modifiers: [.declaration])
      return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .enum, modifiers: [.declaration])
      return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .actor, modifiers: [.declaration])
      return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
      emit(node.name, kind: .interface, modifiers: [.declaration])
      return .visitChildren
    }

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
      emit(node.name, kind: isInTypeMemberScope(node) ? .method : .function, modifiers: modifiers)
      return .visitChildren
    }

    // MARK: Variable and property declarations
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
      var modifiers: SemanticTokenModifiers = [.declaration]
      if let varDecl = node.parent?.parent?.as(VariableDeclSyntax.self),
        varDecl.modifiers.contains(where: {
          $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        })
      {
        modifiers.insert(.static)
      }
      let kind: SemanticTokenTypes = isInTypeMemberScope(node) ? .property : .variable
      emitAllIdentifiers(in: node.pattern, kind: kind, modifiers: modifiers)
      return .visitChildren
    }

    private func emitAllIdentifiers(in pattern: PatternSyntax, kind: SemanticTokenTypes, modifiers: SemanticTokenModifiers) {
      if let idPattern = pattern.as(IdentifierPatternSyntax.self) {
        emit(idPattern.identifier, kind: kind, modifiers: modifiers)
      } else if let tuplePattern = pattern.as(TuplePatternSyntax.self) {
        for element in tuplePattern.elements {
          emitAllIdentifiers(in: element.pattern, kind: kind, modifiers: modifiers)
        }
      } else if let valueBinding = pattern.as(ValueBindingPatternSyntax.self) {
        emitAllIdentifiers(in: valueBinding.pattern, kind: kind, modifiers: modifiers)
      }
    }

    // MARK: Optional binding conditions (if let x = ..., guard let x = ...)
    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
      emitAllIdentifiers(in: node.pattern, kind: .variable, modifiers: [.declaration])
      return .visitChildren
    }

    // MARK: Switch case patterns (case let x, case let (a, b))
    override func visit(_ node: SwitchCaseItemSyntax) -> SyntaxVisitorContinueKind {
      emitAllIdentifiers(in: node.pattern, kind: .variable, modifiers: [.declaration])
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
