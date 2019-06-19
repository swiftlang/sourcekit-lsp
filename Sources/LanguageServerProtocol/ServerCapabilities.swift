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

  public var textDocumentSync: TextDocumentSyncOptions?

  /// Whether the server provides code-completion.
  public var completionProvider: CompletionOptions?

  /// Whether the server provides "textDocument/hover".
  public var hoverProvider: Bool?

  /// Whether the server provides "textDocument/definition".
  public var definitionProvider: Bool?

  /// Whether the server provides "textDocument/references".
  public var referencesProvider: Bool?

  /// Whether the server provides "textDocument/documentHighlight".
  public var documentHighlightProvider: Bool?

  /// Whether the server provides "textDocument/formatting".
  public var documentFormattingProvider: Bool?

  /// Whether the server provides "textDocument/rangeFormatting".
  public var documentRangeFormattingProvider: Bool?

  /// Whether the server provides "textDocument/onTypeFormatting".
  public var documentOnTypeFormattingProvider: DocumentOnTypeFormattingOptions?

  /// Whether the server provides "textDocument/foldingRange".
  public var foldingRangeProvider: Bool?

  /// Whether the server provides "textDocument/documentSymbol"
  public var documentSymbolProvider: Bool?

  /// Whether the server provides "textDocument/documentColor" and "textDocument/colorPresentation".
  public var colorProvider: Bool?

  /// Whether the server provides "textDocument/codeAction".
  public var codeActionProvider: CodeActionServerCapabilities?

  /// Whether the server provides "workspace/executeCommand".
  public var executeCommandProvider: ExecuteCommandOptions?

  // TODO: fill-in the rest.

  public init(
    textDocumentSync: TextDocumentSyncOptions? = nil,
    completionProvider: CompletionOptions? = nil,
    hoverProvider: Bool? = nil,
    definitionProvider: Bool? = nil,
    referencesProvider: Bool? = nil,
    documentHighlightProvider: Bool? = nil,
    documentFormattingProvider: Bool? = nil,
    documentRangeFormattingProvider: Bool? = nil,
    documentOnTypeFormattingProvider: DocumentOnTypeFormattingOptions? = nil,
    foldingRangeProvider: Bool? = nil,
    documentSymbolProvider: Bool? = nil,
    colorProvider: Bool? = nil,
    codeActionProvider: CodeActionServerCapabilities? = nil,
    executeCommandProvider: ExecuteCommandOptions? = nil
    )
  {
    self.textDocumentSync = textDocumentSync
    self.completionProvider = completionProvider
    self.hoverProvider = hoverProvider
    self.definitionProvider = definitionProvider
    self.referencesProvider = referencesProvider
    self.documentHighlightProvider = documentHighlightProvider
    self.documentFormattingProvider = documentFormattingProvider
    self.documentRangeFormattingProvider = documentRangeFormattingProvider
    self.documentOnTypeFormattingProvider = documentOnTypeFormattingProvider
    self.foldingRangeProvider = foldingRangeProvider
    self.documentSymbolProvider = documentSymbolProvider
    self.colorProvider = colorProvider
    self.codeActionProvider = codeActionProvider
    self.executeCommandProvider = executeCommandProvider
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.completionProvider = try container.decodeIfPresent(CompletionOptions.self, forKey: .completionProvider)
    self.hoverProvider = try container.decodeIfPresent(Bool.self, forKey: .hoverProvider)
    self.definitionProvider = try container.decodeIfPresent(Bool.self, forKey: .definitionProvider)
    self.foldingRangeProvider = try container.decodeIfPresent(Bool.self, forKey: .foldingRangeProvider)
    self.documentSymbolProvider = try container.decodeIfPresent(Bool.self, forKey: .documentSymbolProvider)
    self.colorProvider = try container.decodeIfPresent(Bool.self, forKey: .colorProvider)
    self.codeActionProvider = try container.decodeIfPresent(CodeActionServerCapabilities.self, forKey: .codeActionProvider)
    self.executeCommandProvider = try container.decodeIfPresent(ExecuteCommandOptions.self, forKey: .executeCommandProvider)

    if let textDocumentSync = try? container.decode(TextDocumentSyncOptions.self, forKey: .textDocumentSync) {
      self.textDocumentSync = textDocumentSync

    } else if let kind = try? container.decode(TextDocumentSyncKind.self, forKey: .textDocumentSync) {
      // Legacy response
      self.textDocumentSync = TextDocumentSyncOptions(openClose: nil, change: kind, willSave: nil, willSaveWaitUntil: nil, save: nil)

    } else {
      self.textDocumentSync = nil
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

  public init(openClose: Bool? = true, change: TextDocumentSyncKind? = .incremental, willSave: Bool? = true, willSaveWaitUntil: Bool? = false, save: SaveOptions? = SaveOptions()) {
    self.openClose = openClose
    self.change = change
    self.willSave = willSave
    self.willSaveWaitUntil = willSaveWaitUntil
    self.save = save
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

public struct ExecuteCommandOptions: Codable, Hashable {

  /// The commands to be executed on this server.
  public var commands: [String]

  public init(commands: [String]) {
    self.commands = commands
  }
}
