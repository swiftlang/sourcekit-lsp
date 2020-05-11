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

  /// Defines how text documents are synced. Is either a detailed structure defining each notification or
  /// for backwards compatibility the TextDocumentSyncKind number. If omitted it defaults to `TextDocumentSyncKind.None`.
  public var textDocumentSync: TextDocumentSyncOptions?

  /// Whether the server provides "textDocument/hover".
  public var hoverProvider: Bool?

  /// Whether the server provides code-completion.
  public var completionProvider: CompletionOptions?

  /// The server provides signature help support.
  public var signatureHelpProvider: SignatureHelpOptions?

  /// Whether the server provides "textDocument/definition".
  public var definitionProvider: Bool?

  /// The server provides Goto Type Definition support.
  public var typeDefinitionProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides "textDocument/implementation".
  public var implementationProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>?

  /// Whether the server provides "textDocument/references".
  public var referencesProvider: Bool?

  /// Whether the server provides "textDocument/documentHighlight".
  public var documentHighlightProvider: Bool?

  /// Whether the server provides "textDocument/documentSymbol"
  public var documentSymbolProvider: Bool?

  /// The server provides workspace symbol support.
  public var workspaceSymbolProvider: Bool?

  /// Whether the server provides "textDocument/codeAction".
  public var codeActionProvider: ValueOrBool<CodeActionServerCapabilities>?

  /// The server provides code lens.
  public var codeLensProvider: CodeLensOptions?

  /// Whether the server provides "textDocument/formatting".
  public var documentFormattingProvider: Bool?

  /// Whether the server provides "textDocument/rangeFormatting".
  public var documentRangeFormattingProvider: Bool?

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

  public var experimental: LSPAny?

  public init(
    textDocumentSync: TextDocumentSyncOptions? = nil,
    hoverProvider: Bool? = nil,
    completionProvider: CompletionOptions? = nil,
    signatureHelpProvider: SignatureHelpOptions? = nil,
    definitionProvider: Bool? = nil,
    typeDefinitionProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    implementationProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    referencesProvider: Bool? = nil,
    documentHighlightProvider: Bool? = nil,
    documentSymbolProvider: Bool? = nil,
    workspaceSymbolProvider: Bool? = nil,
    codeActionProvider: ValueOrBool<CodeActionServerCapabilities>? = nil,
    codeLensProvider: CodeLensOptions? = nil,
    documentFormattingProvider: Bool? = nil,
    documentRangeFormattingProvider: Bool? = nil,
    documentOnTypeFormattingProvider: DocumentOnTypeFormattingOptions? = nil,
    renameProvider: ValueOrBool<RenameOptions>? = nil,
    documentLinkProvider: DocumentLinkOptions? = nil,
    colorProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    foldingRangeProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    declarationProvider: ValueOrBool<TextDocumentAndStaticRegistrationOptions>? = nil,
    executeCommandProvider: ExecuteCommandOptions? = nil,
    workspace: WorkspaceServerCapabilities? = nil,
    experimental: LSPAny? = nil
  )
  {
    self.textDocumentSync = textDocumentSync
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
    self.experimental = experimental
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

public struct TextDocumentSyncOptions: Codable, Hashable {

  /// Whether open/close notifications should be sent to the server.
  public var openClose: Bool?

  /// Whether and how the client should synchronize document changes with the server.
  public var change: TextDocumentSyncKind?

  /// Whether will-save notifications should be sent to the server.
  public var willSave: Bool?

  /// Whether will-save-wait-until notifications should be sent to the server.
  public var willSaveWaitUntil: Bool?

  public struct SaveOptions: Codable, Hashable {

    /// Whether the client should include the file content in save notifications.
    public var includeText: Bool

    public init(includeText: Bool = false) {
      self.includeText = includeText
    }
  }

  /// Whether save notifications should be sent to the server.
  public var save: SaveOptions?

  public init(openClose: Bool? = true,
              change: TextDocumentSyncKind? = .incremental,
              willSave: Bool? = true,
              willSaveWaitUntil: Bool? = false,
              save: SaveOptions? = SaveOptions()) {
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
      self.save = try container.decodeIfPresent(SaveOptions.self, forKey: .save)
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

  case none = 0

  /// Documents are synced by sending the full content.
  case full = 1

  /// Documents are synced by sending incremental updates.
  case incremental = 2
}

public struct CompletionOptions: Codable, Hashable {

  /// Whether to use `textDocument/resolveCompletion`
  public var resolveProvider: Bool?

  /// The characters that should trigger automatic completion.
  public var triggerCharacters: [String]

  public init(resolveProvider: Bool? = false, triggerCharacters: [String]) {
    self.resolveProvider = resolveProvider
    self.triggerCharacters = triggerCharacters
  }
}

public struct SignatureHelpOptions: Codable, Hashable {
  /// The characters that trigger signature help automatically.
  public var triggerCharacters: [String]?

  public init(triggerCharacters: [String]? = nil) {
    self.triggerCharacters = triggerCharacters
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

public typealias DocumentSelector = [DocumentFilter]

public struct TextDocumentAndStaticRegistrationOptions: Codable, Hashable {
  /// A document selector to identify the scope of the registration. If set to null the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  /// The id used to register the request. The id can be used to deregister the request again. See also Registration#id
  public var id: String?

  public init(documentSelector: DocumentSelector? = nil, id: String? = nil) {
    self.documentSelector = documentSelector
    self.id = id
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

public struct CodeActionOptions: Codable, Hashable {

  /// CodeActionKinds that this server may return.
  public var codeActionKinds: [CodeActionKind]?

  public init(codeActionKinds: [CodeActionKind]?) {
    self.codeActionKinds = codeActionKinds
  }
}

public struct CodeLensOptions: Codable, Hashable {
  /// Code lens has a resolve provider as well.
  public var resolveProvider: Bool?

  public init(resolveProvider: Bool? = nil) {
    self.resolveProvider = resolveProvider
  }
}

public struct ExecuteCommandOptions: Codable, Hashable {

  /// The commands to be executed on this server.
  public var commands: [String]

  public init(commands: [String]) {
    self.commands = commands
  }
}

public struct RenameOptions: Codable, Hashable {
  /// Renames should be checked and tested before being executed.
  public var prepareProvider: Bool?

  public init(prepareProvider: Bool? = nil) {
    self.prepareProvider = prepareProvider
  }
}

public struct DocumentLinkOptions: Codable, Hashable {
  /// Document links have a resolve provider as well.
  public var resolveProvider: Bool?

  public init(resolveProvider: Bool? = nil) {
    self.resolveProvider = resolveProvider
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

  public var workspaceFolders: WorkspaceFolders?

  public init(workspaceFolders: WorkspaceFolders? = nil) {
    self.workspaceFolders = workspaceFolders
  }
}
