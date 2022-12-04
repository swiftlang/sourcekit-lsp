//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Capabilities provided by the language server.
public struct ServerCapabilities: Codable, Hashable {

  /// The position encoding the server picked from the encodings offered
  /// by the client via the client capability `general.positionEncodings`.
  ///
  /// If the client didn't provide any position encodings the only valid
  /// value that a server can return is 'utf-16'.
  ///
  /// If omitted it defaults to 'utf-16'.
  public var positionEncoding: PositionEncodingKind?

  /// Defines how text documents are synced. Is either a detailed structure defining each notification or
  /// for backwards compatibility the TextDocumentSyncKind number. If omitted it defaults to `TextDocumentSyncKind.None`.
  public var textDocumentSync: TextDocumentSync?

  /// Defines how notebook documents are synced.
  public var notebookDocumentSync: NotebookDocumentSyncAndStaticRegistrationOptions?

  /// Whether the server provides "textDocument/hover".
  public var hoverProvider: ValueOrBool<HoverOptions>?

  /// Whether the server provides code-completion.
  public var completionProvider: CompletionOptions?

  /// The server provides signature help support.
  public var signatureHelpProvider: SignatureHelpOptions?

  /// Whether the server provides "textDocument/definition".
  public var definitionProvider: ValueOrBool<DefinitionOptions>?

  /// The server provides Goto Type Definition support.
  public var typeDefinitionProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides "textDocument/implementation".
  public var implementationProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides "textDocument/references".
  public var referencesProvider: ValueOrBool<ReferenceOptions>?

  /// Whether the server provides "textDocument/documentHighlight".
  public var documentHighlightProvider: ValueOrBool<DocumentHighlightOptions>?

  /// Whether the server provides "textDocument/documentSymbol"
  public var documentSymbolProvider: ValueOrBool<DocumentSymbolOptions>?

  /// The server provides workspace symbol support.
  public var workspaceSymbolProvider: ValueOrBool<WorkspaceSymbolOptions>?

  /// Whether the server provides "textDocument/codeAction".
  public var codeActionProvider: ValueOrBool<CodeActionServerCapabilities>?

  /// The server provides code lens.
  public var codeLensProvider: CodeLensOptions?

  /// Whether the server provides "textDocument/formatting".
  public var documentFormattingProvider: ValueOrBool<DocumentFormattingOptions>?

  /// Whether the server provides "textDocument/rangeFormatting".
  public var documentRangeFormattingProvider: ValueOrBool<DocumentRangeFormattingOptions>?

  /// Whether the server provides "textDocument/onTypeFormatting".
  public var documentOnTypeFormattingProvider: DocumentOnTypeFormattingOptions?

  /// The server provides rename support. RenameOptions may only be specified if the client states that it supports `prepareSupport` in its initial `initialize` request.
  public var renameProvider: ValueOrBool<RenameOptions>?

  /// The server provides document link support.
  public var documentLinkProvider: DocumentLinkOptions?

  /// Whether the server provides "textDocument/documentColor" and "textDocument/colorPresentation".
  public var colorProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides "textDocument/foldingRange".
  public var foldingRangeProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  public var declarationProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides "workspace/executeCommand".
  public var executeCommandProvider: ExecuteCommandOptions?

  public var workspace: WorkspaceServerCapabilities?

  /// Whether the server provides `textDocument/prepareCallHierarchy` and related
  /// call hierarchy requests.
  public var callHierarchyProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides `textDocument/prepareTypeHierarchy` and related
  /// type hierarchy requests.
  public var typeHierarchyProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server supports the `textDocument/semanticTokens` family of
  /// requests.
  public var semanticTokensProvider: SemanticTokensOptions?

  /// Whether the server supports the `textDocument/inlayHint` family of requests.
  public var inlayHintProvider: InlayHintOptions?

  /// Whether the server provides selection range support.
  public var selectionRangeProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides link editing range support.
  public var linkedEditingRangeProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether server provides moniker support.
  public var monikerProvider: ValueOrBool<MonikerOptions>?

  /// The server provides inline values.
  public var inlineValueProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  public var experimental: LSPAny?

  public init(
    positionEncoding: PositionEncodingKind? = nil,
    textDocumentSync: TextDocumentSync? = nil,
    notebookDocumentSync: NotebookDocumentSyncAndStaticRegistrationOptions? = nil,
    hoverProvider: ValueOrBool<HoverOptions>? = nil,
    completionProvider: CompletionOptions? = nil,
    signatureHelpProvider: SignatureHelpOptions? = nil,
    definitionProvider: ValueOrBool<DefinitionOptions>? = nil,
    typeDefinitionProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    implementationProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    referencesProvider: ValueOrBool<ReferenceOptions>? = nil,
    documentHighlightProvider: ValueOrBool<DocumentHighlightOptions>? = nil,
    documentSymbolProvider: ValueOrBool<DocumentSymbolOptions>? = nil,
    workspaceSymbolProvider: ValueOrBool<WorkspaceSymbolOptions>? = nil,
    codeActionProvider: ValueOrBool<CodeActionServerCapabilities>? = nil,
    codeLensProvider: CodeLensOptions? = nil,
    documentFormattingProvider: ValueOrBool<DocumentFormattingOptions>? = nil,
    documentRangeFormattingProvider: ValueOrBool<DocumentRangeFormattingOptions>? = nil,
    documentOnTypeFormattingProvider: DocumentOnTypeFormattingOptions? = nil,
    renameProvider: ValueOrBool<RenameOptions>? = nil,
    documentLinkProvider: DocumentLinkOptions? = nil,
    colorProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    foldingRangeProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    declarationProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    executeCommandProvider: ExecuteCommandOptions? = nil,
    workspace: WorkspaceServerCapabilities? = nil,
    callHierarchyProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    typeHierarchyProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    semanticTokensProvider: SemanticTokensOptions? = nil,
    inlayHintProvider: InlayHintOptions? = nil,
    selectionRangeProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    linkedEditingRangeProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    monikerProvider: ValueOrBool<MonikerOptions>? = nil,
    inlineValueProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    experimental: LSPAny? = nil
  )
  {
    self.positionEncoding = positionEncoding
    self.textDocumentSync = textDocumentSync
    self.notebookDocumentSync = notebookDocumentSync
    self.hoverProvider = hoverProvider
    self.completionProvider = completionProvider
    self.signatureHelpProvider = signatureHelpProvider
    self.definitionProvider = definitionProvider
    self.typeDefinitionProvider = typeDefinitionProvider
    self.implementationProvider = implementationProvider
    self.referencesProvider = referencesProvider
    self.documentHighlightProvider = documentHighlightProvider
    self.documentSymbolProvider = documentSymbolProvider
    self.workspaceSymbolProvider = workspaceSymbolProvider
    self.codeActionProvider = codeActionProvider
    self.codeLensProvider = codeLensProvider
    self.documentFormattingProvider = documentFormattingProvider
    self.documentRangeFormattingProvider = documentRangeFormattingProvider
    self.documentOnTypeFormattingProvider = documentOnTypeFormattingProvider
    self.renameProvider = renameProvider
    self.documentLinkProvider = documentLinkProvider
    self.colorProvider = colorProvider
    self.foldingRangeProvider = foldingRangeProvider
    self.declarationProvider = declarationProvider
    self.executeCommandProvider = executeCommandProvider
    self.workspace = workspace
    self.callHierarchyProvider = callHierarchyProvider
    self.typeHierarchyProvider = typeHierarchyProvider
    self.semanticTokensProvider = semanticTokensProvider
    self.inlayHintProvider = inlayHintProvider
    self.selectionRangeProvider = selectionRangeProvider
    self.linkedEditingRangeProvider = linkedEditingRangeProvider
    self.experimental = experimental
    self.monikerProvider = monikerProvider
    self.inlineValueProvider = inlineValueProvider
  }
}

public enum ValueOrBool<ValueType: Codable>: Codable, Hashable where ValueType: Hashable {
  case bool(Bool)
  case value(ValueType)

  /// A option is supported if either its bool value is `true` or the value is specified
  public var isSupported: Bool {
    switch self {
    case .bool(let value):
      return value
    case .value(_):
      return true
    }
  }

  public init(from decoder: Decoder) throws {
    if let bool = try? Bool(from: decoder) {
      self = .bool(bool)
    } else if let value = try? ValueType(from: decoder) {
      self = .value(value)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Bool or \(ValueType.self)")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .bool(let bool):
      try bool.encode(to: encoder)
    case .value(let value):
      try value.encode(to: encoder)
    }
  }
}

public enum TextDocumentSync: Codable, Hashable {
  case options(TextDocumentSyncOptions)
  case kind(TextDocumentSyncKind)

  public init(from decoder: Decoder) throws {
    if let options = try? TextDocumentSyncOptions(from: decoder) {
      self = .options(options)
    } else if let kind = try? TextDocumentSyncKind(from: decoder) {
      self = .kind(kind)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected TextDocumentSyncOptions or TextDocumentSyncKind")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .options(let options):
      try options.encode(to: encoder)
    case .kind(let kind):
      try kind.encode(to: encoder)
    }
  }
}

/// The LSP spec has two definitions of `TextDocumentSyncOptions`, one
/// with `willSave` etc. and one that only contains `openClose` and `change`.
/// Based on the VSCode implementation, the definition that contains `willSave`
/// appears to be the correct one, so we use that one as well.
public struct TextDocumentSyncOptions: Codable, Hashable {

  /// Open and close notifications are sent to the server.
  /// If omitted open close notifications should not be sent.
  public var openClose: Bool?

  /// Change notifications are sent to the server. See
  /// TextDocumentSyncKind.None, TextDocumentSyncKind.Full and
  /// TextDocumentSyncKind.Incremental. If omitted it defaults to
  /// TextDocumentSyncKind.None.
  public var change: TextDocumentSyncKind?

  // NOTE: The following properties are not

  /// Whether will-save notifications should be sent to the server.
  public var willSave: Bool?

  /// Whether will-save-wait-until notifications should be sent to the server.
  public var willSaveWaitUntil: Bool?

  public struct SaveOptions: Codable, Hashable {

    /// Whether the client should include the file content in save notifications.
    public var includeText: Bool?

    public init(includeText: Bool? = nil) {
      self.includeText = includeText
    }
  }

  /// Whether save notifications should be sent to the server.
  public var save: ValueOrBool<SaveOptions>?

  public init(openClose: Bool? = true,
              change: TextDocumentSyncKind? = .incremental,
              willSave: Bool? = true,
              willSaveWaitUntil: Bool? = false,
              save: ValueOrBool<SaveOptions>? = .value(SaveOptions(includeText: false))) {
    self.openClose = openClose
    self.change = change
    self.willSave = willSave
    self.willSaveWaitUntil = willSaveWaitUntil
    self.save = save
  }

  public init(from decoder: Decoder) throws {
    do {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.openClose = try container.decodeIfPresent(Bool.self, forKey: .openClose)
      self.change = try container.decodeIfPresent(TextDocumentSyncKind.self, forKey: .change)
      self.willSave = try container.decodeIfPresent(Bool.self, forKey: .willSave)
      self.willSaveWaitUntil = try container.decodeIfPresent(Bool.self, forKey: .willSaveWaitUntil)
      self.save = try container.decodeIfPresent(ValueOrBool<SaveOptions>.self, forKey: .save)
      return
    } catch {}
    do {
      // Try decoding self as standalone TextDocumentSyncKind
      self.change = try TextDocumentSyncKind(from: decoder)
      return
    } catch {}
    let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected TextDocumentSyncOptions or TextDocumentSyncKind")
    throw DecodingError.dataCorrupted(context)
  }
}

public enum TextDocumentSyncKind: Int, Codable, Hashable {

  /// Documents should not be synced at all.
  case none = 0

  /// Documents are synced by always sending the full content of the document.
  case full = 1

  /// Documents are synced by sending the full content on open.
  /// After that only incremental updates to the document are sent.
  case incremental = 2
}

public enum NotebookFilter: Codable, Hashable {
  case string(String)
  case documentFilter(DocumentFilter)

  public init(from decoder: Decoder) throws {
    if let string = try? String(from: decoder) {
      self = .string(string)
    } else if let documentFilter = try? DocumentFilter(from: decoder) {
      self = .documentFilter(documentFilter)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or DocumentFilter")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .string(let string):
      try string.encode(to: encoder)
    case .documentFilter(let documentFilter):
      try documentFilter.encode(to: encoder)
    }
  }
}
public typealias NotebookSelector = [NotebookFilter]

public struct NotebookDocumentSyncAndStaticRegistrationOptions: Codable, Hashable {
  /// The notebooks to be synced
  public var notebookSelector: NotebookSelector

  /// Whether save notification should be forwarded to
  /// the server. Will only be honored if mode === `notebook`.
  public var save: Bool?

  /// The id used to register the request. The id can be used to deregister the request again. See also Registration#id
  public var id: String?

  public init(
    notebookSelector: NotebookSelector,
    save: Bool? = nil,
    id: String? = nil
  ) {
    self.notebookSelector = notebookSelector
    self.save = save
    self.id = id
  }
}

public protocol WorkDoneProgressOptions {
  var workDoneProgress: Bool?  { get }
}

public struct HoverOptions: WorkDoneProgressOptions, Codable, Hashable {
  public var workDoneProgress: Bool?

  public init(
    workDoneProgress: Bool? = nil
  ) {
    self.workDoneProgress = workDoneProgress
  }
}

public struct CompletionItemOptions: Codable, Hashable {
  /// The server has support for completion item label
  /// details (see also `CompletionItemLabelDetails`) when receiving
  /// a completion item in a resolve call.
  public var labelDetailsSupport: Bool?

  public init(
    labelDetailsSupport: Bool? = false
  ) {
    self.labelDetailsSupport = labelDetailsSupport
  }
}

public struct CompletionOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// Whether to use `textDocument/resolveCompletion`
  public var resolveProvider: Bool?

  /// The characters that should trigger automatic completion.
  public var triggerCharacters: [String]?

  /// The list of all possible characters that commit a completion.
  public var allCommitCharacters: [String]?

  /// The server supports the following `CompletionItem` specific capabilities.
  public var completionItem: CompletionItemOptions?

  public var workDoneProgress: Bool?

  public init(
    resolveProvider: Bool? = false,
    triggerCharacters: [String]? = nil,
    allCommitCharacters: [String]? = nil,
    completionItem: CompletionItemOptions? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.resolveProvider = resolveProvider
    self.triggerCharacters = triggerCharacters
    self.allCommitCharacters = allCommitCharacters
    self.completionItem = completionItem
    self.workDoneProgress = workDoneProgress
  }
}

public struct DefinitionOptions: WorkDoneProgressOptions, Codable, Hashable {
  public var workDoneProgress: Bool?

  public init(
    workDoneProgress: Bool? = nil
  ) {
    self.workDoneProgress = workDoneProgress
  }
}

public struct ReferenceOptions: WorkDoneProgressOptions, Codable, Hashable {
  public var workDoneProgress: Bool?

  public init(
    workDoneProgress: Bool? = nil
  ) {
    self.workDoneProgress = workDoneProgress
  }
}

public struct DocumentHighlightOptions: WorkDoneProgressOptions, Codable, Hashable {
  public var workDoneProgress: Bool?

  public init(
    workDoneProgress: Bool? = nil
  ) {
    self.workDoneProgress = workDoneProgress
  }
}

public struct DocumentSymbolOptions: WorkDoneProgressOptions, Codable, Hashable {
  public var workDoneProgress: Bool?

  public init(
    workDoneProgress: Bool? = nil
  ) {
    self.workDoneProgress = workDoneProgress
  }
}

public struct DocumentFormattingOptions: WorkDoneProgressOptions, Codable, Hashable {
  public var workDoneProgress: Bool?

  public init(
    workDoneProgress: Bool? = nil
  ) {
    self.workDoneProgress = workDoneProgress
  }
}

public struct DocumentRangeFormattingOptions: WorkDoneProgressOptions, Codable, Hashable {
  public var workDoneProgress: Bool?

  public init(
    workDoneProgress: Bool? = nil
  ) {
    self.workDoneProgress = workDoneProgress
  }
}

public struct FoldingRangeOptions: Codable, Hashable {
  /// Currently empty in the spec.
  public init() {}
}

public struct SignatureHelpOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// The characters that trigger signature help automatically.
  public var triggerCharacters: [String]?

  /// List of characters that re-trigger signature help.
  ///
  /// These trigger characters are only active when signature help is already
  /// showing. All trigger characters are also counted as re-trigger
  /// characters.
  public var retriggerCharacters: [String]?

  public var workDoneProgress: Bool?

  public init(
    triggerCharacters: [String]? = nil,
    retriggerCharacters: [String]? = nil
  ) {
    self.triggerCharacters = triggerCharacters
    self.retriggerCharacters = retriggerCharacters
  }
}

public struct DocumentFilter: Codable, Hashable {
  /// A language id, like `typescript`.
  public var language: String?

  /// A Uri scheme, like `file` or `untitled`.
  public var scheme: String?

  /// A glob pattern, like `*.{ts,js}`.
  ///
  /// Glob patterns can have the following syntax:
  /// - `*` to match one or more characters in a path segment
  /// - `?` to match on one character in a path segment
  /// - `**` to match any number of path segments, including none
  /// - `{}` to group conditions (e.g. `**​/*.{ts,js}` matches all TypeScript and JavaScript files)
  /// - `[]` to declare a range of characters to match in a path segment (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
  /// - `[!...]` to negate a range of characters to match in a path segment (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not `example.0`)
  public var pattern: String?

  public init(language: String? = nil, scheme: String? = nil, pattern: String? = nil) {
    self.language = language
    self.scheme = scheme
    self.pattern = pattern
  }
}

extension DocumentFilter: LSPAnyCodable {
  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    if let languageValue = dictionary[CodingKeys.language.stringValue] {
      guard case .string(let language) = languageValue else { return nil }
      self.language = language
    } else {
      self.language = nil
    }
    if let schemeValue = dictionary[CodingKeys.scheme.stringValue] {
      guard case .string(let scheme) = schemeValue else { return nil }
      self.scheme = scheme
    } else {
      self.scheme = nil
    }
    if let patternValue = dictionary[CodingKeys.pattern.stringValue] {
      guard case .string(let pattern) = patternValue else { return nil }
      self.pattern = pattern
    } else {
      self.pattern = nil
    }
  }
  public func encodeToLSPAny() -> LSPAny {
    var dict = [String: LSPAny]()
    if let language = language {
      dict[CodingKeys.language.stringValue] = .string(language)
    }
    if let scheme = scheme {
      dict[CodingKeys.scheme.stringValue] = .string(scheme)
    }
    if let pattern = pattern {
      dict[CodingKeys.pattern.stringValue] = .string(pattern)
    }
    return .dictionary(dict)
  }
}

public typealias DocumentSelector = [DocumentFilter]

public struct TextDocumentAndStaticRegistrationOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// A document selector to identify the scope of the registration. If set to null the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  /// The id used to register the request. The id can be used to deregister the request again. See also Registration#id
  public var id: String?

  public var workDoneProgress: Bool?

  public init(
    documentSelector: DocumentSelector? = nil,
    id: String? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.documentSelector = documentSelector
    self.id = id
    self.workDoneProgress = workDoneProgress
  }
}

public struct DocumentOnTypeFormattingOptions: Codable, Hashable {

  /// A character that sould trigger formatting (e.g. '}').
  public var firstTriggerCharacter: String

  /// Additional triggers.
  ///
  /// - note: The lack of plural matches the protocol.
  public var moreTriggerCharacter: [String]?

  public init(triggerCharacters: [String]) {
    self.firstTriggerCharacter = triggerCharacters.first!
    self.moreTriggerCharacter = Array(triggerCharacters.dropFirst())
  }
}

/// Wrapper type for a server's CodeActions' capabilities.
/// If the client supports CodeAction literals, the server can return specific information about
/// how CodeActions will be sent. Otherwise, the server's capabilities are determined by a boolean.
public enum CodeActionServerCapabilities: Codable, Hashable {

  case supportsCodeActionRequests(Bool)
  case supportsCodeActionRequestsWithLiterals(CodeActionOptions)

  public init(clientCapabilities: TextDocumentClientCapabilities.CodeAction?,
              codeActionOptions: CodeActionOptions,
              supportsCodeActions: Bool) {
    if clientCapabilities?.codeActionLiteralSupport != nil {
      self = .supportsCodeActionRequestsWithLiterals(codeActionOptions)
    } else {
      self = .supportsCodeActionRequests(supportsCodeActions)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let supportsCodeActions = try? container.decode(Bool.self) {
      self = .supportsCodeActionRequests(supportsCodeActions)
    } else if let codeActionOptions = try? container.decode(CodeActionOptions.self) {
      self = .supportsCodeActionRequestsWithLiterals(codeActionOptions)
    } else {
      let error = "CodeActionServerCapabilities cannot be decoded: Unrecognized type."
      throw DecodingError.dataCorruptedError(in: container, debugDescription: error)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .supportsCodeActionRequestsWithLiterals(let codeActionOptions):
      try container.encode(codeActionOptions)
    case .supportsCodeActionRequests(let supportCodeActions):
      try container.encode(supportCodeActions)
    }
  }
}

public struct CodeActionOptions: WorkDoneProgressOptions, Codable, Hashable {

  /// CodeActionKinds that this server may return.
  public var codeActionKinds: [CodeActionKind]?

  /// The server provides support to resolve additional
  /// information for a code action.
  public var resolveProvider: Bool?

  public var workDoneProgress: Bool?

  public init(
    codeActionKinds: [CodeActionKind]?,
    resolveProvider: Bool? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.codeActionKinds = codeActionKinds
    self.resolveProvider = resolveProvider
    self.workDoneProgress = workDoneProgress
  }
}

public struct CodeLensOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// Code lens has a resolve provider as well.
  public var resolveProvider: Bool?

  public var workDoneProgress: Bool?

  public init(
    resolveProvider: Bool? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.resolveProvider = resolveProvider
    self.workDoneProgress = workDoneProgress
  }
}

public struct ExecuteCommandOptions: WorkDoneProgressOptions, Codable, Hashable {

  /// The commands to be executed on this server.
  public var commands: [String]

  public var workDoneProgress: Bool?

  public init(
    commands: [String],
    workDoneProgress: Bool? = nil
  ) {
    self.commands = commands
    self.workDoneProgress = workDoneProgress
  }
}

public struct RenameOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// Renames should be checked and tested before being executed.
  public var prepareProvider: Bool?

  public var workDoneProgress: Bool?

  public init(
    prepareProvider: Bool? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.prepareProvider = prepareProvider
    self.workDoneProgress = workDoneProgress
  }
}

public struct DocumentLinkOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// Document links have a resolve provider as well.
  public var resolveProvider: Bool?

  public var workDoneProgress: Bool?

  public init(
    resolveProvider: Bool? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.resolveProvider = resolveProvider
    self.workDoneProgress = workDoneProgress
  }
}

public struct SemanticTokensOptions: WorkDoneProgressOptions, Codable, Hashable {

  public struct SemanticTokensRangeOptions: Equatable, Hashable, Codable {
    // Empty in the LSP 3.16 spec.
  }

  public struct SemanticTokensFullOptions: Equatable, Hashable, Codable {
    /// The server supports deltas for full documents.
    public var delta: Bool?

    public init(delta: Bool? = nil) {
      self.delta = delta
    }
  }

  /// The legend used by the server.
  public var legend: SemanticTokensLegend

  /// Server supports providing semantic tokens for a specific range
  /// of a document.
  public var range: ValueOrBool<SemanticTokensRangeOptions>?

  /// Server supports providing semantic tokens for a full document.
  public var full: ValueOrBool<SemanticTokensFullOptions>?

  public var workDoneProgress: Bool?

  public init(
    legend: SemanticTokensLegend,
    range: ValueOrBool<SemanticTokensRangeOptions>? = nil,
    full: ValueOrBool<SemanticTokensFullOptions>? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.legend = legend
    self.range = range
    self.full = full
    self.workDoneProgress = workDoneProgress
  }
}

public struct InlayHintOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// The server provides support to resolve additional information
  /// for an inlay hint item.
  public var resolveProvider: Bool?

  /// A document selector to identify the scope of the registration. If set to null the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  /// The id used to register the request. The id can be used to deregister the request again. See also Registration#id
  public var id: String?

  public var workDoneProgress: Bool?

  public init(
    resolveProvider: Bool? = nil,
    documentSelector: DocumentSelector? = nil,
    id: String? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.resolveProvider = resolveProvider
    self.documentSelector = documentSelector
    self.id = id
    self.workDoneProgress = workDoneProgress
  }
}

public struct WorkspaceSymbolOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// The server provides support to resolve additional information
  /// for an inlay hint item.
  public var resolveProvider: Bool?

  public var workDoneProgress: Bool?

  public init(
    resolveProvider: Bool? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.resolveProvider = resolveProvider
    self.workDoneProgress = workDoneProgress
  }
}

public struct MonikerOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// A document selector to identify the scope of the registration. If set to null the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  public var workDoneProgress: Bool?

  public init(
    documentSelector: DocumentSelector? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.documentSelector = documentSelector
    self.workDoneProgress = workDoneProgress
  }
}

public struct DiagnosticOptions: WorkDoneProgressOptions, Codable, Hashable {
  /// An optional identifier under which the diagnostics are managed by the client.
  public var identifier: String?

  /// Whether the language has inter file dependencies meaning that
  /// editing code in one file can result in a different diagnostic
  /// set in another file. Inter file dependencies are common for
  /// most programming languages and typically uncommon for linters.
  public var interFileDependencies: Bool

  /// The server provides support for workspace diagnostics as well.
  public var workspaceDiagnostics: Bool

  /// A document selector to identify the scope of the registration. If set to null the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  /// The id used to register the request. The id can be used to deregister the request again. See also Registration#id
  public var id: String?

  public var workDoneProgress: Bool?

  public init(
    identifier: String? = nil,
    interFileDependencies: Bool,
    workspaceDiagnostics: Bool,
    documentSelector: DocumentSelector? = nil,
    id: String? = nil,
    workDoneProgress: Bool? = nil
  ) {
    self.identifier = identifier
    self.interFileDependencies = interFileDependencies
    self.workspaceDiagnostics = workspaceDiagnostics
    self.documentSelector = documentSelector
    self.id = id
    self.workDoneProgress = workDoneProgress
  }
}

public struct WorkspaceServerCapabilities: Codable, Hashable {
  public struct WorkspaceFolders: Codable, Hashable {
    /// The server has support for workspace folders
    public var supported: Bool?

    /// Whether the server wants to receive workspace folder change notifications.
    ///
    /// If a strings is provided the string is treated as a ID under which the notification is registered on the client side. The ID can be used to unregister for these events using the `client/unregisterCapability` request.
    public var changeNotifications: ValueOrBool<String>?

    public init(supported: Bool? = nil, changeNotifications: ValueOrBool<String>? = nil) {
      self.supported = supported
      self.changeNotifications = changeNotifications
    }
  }

  public enum FileOperationPatternKind: String, Codable, Hashable {
    /// The pattern matches a file only.
    case file = "file"
    /// The pattern matches a folder only.
    case folder = "folder"
  }

  public struct FileOperationPatternOptions: Codable, Hashable {
    /// The pattern should be matched ignoring casing
    public var ignoreCase: Bool?

    public init(ignoreCase: Bool? = nil) {
      self.ignoreCase = ignoreCase
    }
  }

  public struct FileOperationPattern: Codable, Hashable {
    /// The glob pattern to match. Glob patterns can have the following syntax:
    /// - `*` to match one or more characters in a path segment
    /// - `?` to match on one character in a path segment
    /// - `**` to match any number of path segments, including none
    /// - `{}` to group sub patterns into an OR expression. (e.g. `**​/*.{ts,js}`
    /// matches all TypeScript and JavaScript files)
    /// - `[]` to declare a range of characters to match in a path segment
    ///   (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
    /// - `[!...]` to negate a range of characters to match in a path segment
    ///   (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but
    ///   not `example.0`)
    public var glob: String

    /// Whether to match files or folders with this pattern. Matches both if undefined.
    public var matches: FileOperationPatternKind?

    /// Additional options used during matching.
    public var options: FileOperationPatternOptions?

    public init(
      glob: String,
      matches: FileOperationPatternKind? = nil,
      options: FileOperationPatternOptions? = nil
    ) {
      self.glob = glob
      self.matches = matches
      self.options = options
    }
  }

  public struct FileOperationFilter: Codable, Hashable {
    /// A Uri like `file` or `untitled`.
    public var scheme: String?

    /// The actual file operation pattern.
    public var pattern: FileOperationPattern

    public init(
      scheme: String? = nil,
      pattern: FileOperationPattern
    ) {
      self.scheme = scheme
      self.pattern = pattern
    }
  }

  public struct FileOperationRegistrationOptions: Codable, Hashable {
    /// The actual filters.
    public var filters: [FileOperationFilter]

    public init(
      filters: [FileOperationFilter]
    ) {
      self.filters = filters
    }
  }

  public struct FileOperationOptions: Codable, Hashable {
    /// The server is interested in receiving didCreateFiles notifications.
    public var didCreate: FileOperationRegistrationOptions?

    /// The server is interested in receiving willCreateFiles notifications.
    public var willCreate: FileOperationRegistrationOptions?

    /// The server is interested in receiving didRenameFiles notifications.
    public var didRename: FileOperationRegistrationOptions?

    /// The server is interested in receiving willRenameFiles notifications.
    public var willRename: FileOperationRegistrationOptions?

    /// The server is interested in receiving didDeleteFiles notifications.
    public var didDelete: FileOperationRegistrationOptions?

    /// The server is interested in receiving willDeleteFiles notifications.
    public var willDelete: FileOperationRegistrationOptions?
  }

  /// The server supports workspace folder.
  public var workspaceFolders: WorkspaceFolders?

  public init(workspaceFolders: WorkspaceFolders? = nil) {
    self.workspaceFolders = workspaceFolders
  }
}
