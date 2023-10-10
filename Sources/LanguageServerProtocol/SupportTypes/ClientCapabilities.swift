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

/// Capabilities provided by the client editor/IDE.
public struct ClientCapabilities: Hashable, Codable {

  /// Workspace-specific client capabilities.
  public var workspace: WorkspaceClientCapabilities?

  /// Document-specific client capabilities.
  public var textDocument: TextDocumentClientCapabilities?

  /// Capabilities specific to the notebook document support.
  public var notebookDocument: NotebookDocumentClientCapabilities?

  /// Window specific client capabilities.
  public var window: WindowClientCapabilities?

  /// General client capabilities.
  public var general: GeneralClientCapabilities?

  /// Experimental client capabilities.
  public var experimental: LSPAny?

  public init(
    workspace: WorkspaceClientCapabilities? = nil,
    textDocument: TextDocumentClientCapabilities? = nil,
    notebookDocument: NotebookDocumentClientCapabilities? = nil,
    window: WindowClientCapabilities? = nil,
    general: GeneralClientCapabilities? = nil,
    experimental: LSPAny? = nil
  ) {
    self.workspace = workspace
    self.textDocument = textDocument
    self.notebookDocument = notebookDocument
    self.window = window
    self.general = general
    self.experimental = experimental
  }
}

/// Helper capability wrapper for structs that only have a `dynamicRegistration` member.
public struct DynamicRegistrationCapability: Hashable, Codable {
  /// Whether the client supports dynamic registaration of this feature.
  public var dynamicRegistration: Bool? = nil

  public init(dynamicRegistration: Bool? = nil) {
    self.dynamicRegistration = dynamicRegistration
  }
}

/// Helper capability wrapper for structs that only have a `refreshSupport` member.
public struct RefreshRegistrationCapability: Hashable, Codable {
  /// Whether the client implementation supports a refresh request sent from the
  /// server to the client.
  public var refreshSupport: Bool?

  public init(refreshSupport: Bool? = nil) {
    self.refreshSupport = refreshSupport
  }
}

/// Capabilities of the client editor/IDE related to managing the workspace.
// FIXME: Instead of making all of these optional, provide default values and make the deserialization handle missing values.
public struct WorkspaceClientCapabilities: Hashable, Codable {

  /// Capabilities specific to `WorkspaceEdit`.
  public struct WorkspaceEdit: Hashable, Codable {
    /// Whether the client supports the `documentChanges` field of `WorkspaceEdit`.
    public var documentChanges: Bool? = nil

    public init(documentChanges: Bool? = nil) {
      self.documentChanges = documentChanges
    }
  }

  /// Capabilities specific to the `workspace/symbol` request.
  public struct Symbol: Hashable, Codable {

    /// Capabilities specific to `SymbolKind`.
    public struct SymbolKind: Hashable, Codable {

      /// The symbol kind values that the client can support.
      ///
      /// If not specified, the client support only the kinds from `File` to `Array` from LSP 1.
      ///
      /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
      public var valueSet: [LanguageServerProtocol.SymbolKind]? = nil

      public init(valueSet: [LanguageServerProtocol.SymbolKind]? = nil) {
        self.valueSet = valueSet
      }
    }

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    public var symbolKind: SymbolKind? = nil

    public init(dynamicRegistration: Bool? = nil, symbolKind: SymbolKind? = nil) {
      self.dynamicRegistration = dynamicRegistration
      self.symbolKind = symbolKind
    }
  }

  public struct FileOperations: Hashable, Codable {
    /// Whether the client supports dynamic registration for file
    /// requests/notifications.
    public var dynamicRegistration: Bool?

    /// The client has support for sending didCreateFiles notifications.
    public var didCreate: Bool?

    /// The client has support for sending willCreateFiles requests.
    public var willCreate: Bool?

    /// The client has support for sending didRenameFiles notifications.
    public var didRename: Bool?

    /// The client has support for sending willRenameFiles requests.
    public var willRename: Bool?

    /// The client has support for sending didDeleteFiles notifications.
    public var didDelete: Bool?

    /// The client has support for sending willDeleteFiles requests.
    public var willDelete: Bool?

    public init(
      dynamicRegistration: Bool? = nil,
      didCreate: Bool? = nil,
      willCreate: Bool? = nil,
      didRename: Bool? = nil,
      willRename: Bool? = nil,
      didDelete: Bool? = nil,
      willDelete: Bool? = nil
    ) {
      self.dynamicRegistration = dynamicRegistration
      self.didCreate = didCreate
      self.willCreate = willCreate
      self.didRename = didRename
      self.willRename = willRename
      self.didDelete = didDelete
      self.willDelete = willDelete
    }
  }

  // MARK: Properties

  /// Whether the client can apply text edits via the `workspace/applyEdit` request.
  public var applyEdit: Bool? = nil

  public var workspaceEdit: WorkspaceEdit? = nil

  public var didChangeConfiguration: DynamicRegistrationCapability? = nil

  /// Whether the clients supports file watching - note that the protocol currently doesn't
  /// support static registration for file changes.
  public var didChangeWatchedFiles: DynamicRegistrationCapability? = nil

  public var symbol: Symbol? = nil

  public var executeCommand: DynamicRegistrationCapability? = nil

  /// Whether the client supports workspace folders.
  public var workspaceFolders: Bool? = nil

  /// Whether the client supports the `workspace/configuration` request.
  public var configuration: Bool? = nil

  public var semanticTokens: RefreshRegistrationCapability? = nil

  public var codeLens: RefreshRegistrationCapability? = nil

  public var fileOperations: FileOperations? = nil

  public var inlineValue: RefreshRegistrationCapability? = nil

  public var inlayHint: RefreshRegistrationCapability? = nil

  public var diagnostics: RefreshRegistrationCapability? = nil

  public init(
    applyEdit: Bool? = nil,
    workspaceEdit: WorkspaceEdit? = nil,
    didChangeConfiguration: DynamicRegistrationCapability? = nil,
    didChangeWatchedFiles: DynamicRegistrationCapability? = nil,
    symbol: Symbol? = nil,
    executeCommand: DynamicRegistrationCapability? = nil,
    workspaceFolders: Bool? = nil,
    configuration: Bool? = nil,
    semanticTokens: RefreshRegistrationCapability? = nil,
    codeLens: RefreshRegistrationCapability? = nil,
    fileOperations: FileOperations? = nil,
    inlineValue: RefreshRegistrationCapability? = nil,
    inlayHint: RefreshRegistrationCapability? = nil,
    diagnostics: RefreshRegistrationCapability? = nil
  ) {
    self.applyEdit = applyEdit
    self.workspaceEdit = workspaceEdit
    self.didChangeConfiguration = didChangeConfiguration
    self.didChangeWatchedFiles = didChangeWatchedFiles
    self.symbol = symbol
    self.executeCommand = executeCommand
    self.workspaceFolders = workspaceFolders
    self.configuration = configuration
    self.semanticTokens = semanticTokens
    self.codeLens = codeLens
    self.fileOperations = fileOperations
    self.inlineValue = inlineValue
    self.inlayHint = inlayHint
    self.diagnostics = diagnostics
  }
}

/// Capabilities of the client editor/IDE related to the document.
// FIXME: Instead of making all of these optional, provide default values and make the deserialization handle missing values.
public struct TextDocumentClientCapabilities: Hashable, Codable {

  /// Capabilities specific to the `textDocument/...` change notifications.
  public struct Synchronization: Hashable, Codable {

    /// Whether the client supports dynamic registaration of these notifications.
    public var dynamicRegistration: Bool? = nil

    /// Whether the client supports the will-save notification.
    public var willSave: Bool? = nil

    /// Whether the client supports sending a will-save *request* and applies the edits from the response before saving.
    public var willSaveWaitUntil: Bool? = nil

    /// Whether the client supports the did-save notification.
    public var didSave: Bool? = nil

    public init(
      dynamicRegistration: Bool? = nil,
      willSave: Bool? = nil,
      willSaveWaitUntil: Bool? = nil,
      didSave: Bool? = nil
    ) {
      self.dynamicRegistration = dynamicRegistration
      self.willSave = willSave
      self.willSaveWaitUntil = willSaveWaitUntil
      self.didSave = didSave
    }
  }

  /// Capabilities specific to the `textDocument/...` change notifications.
  public struct Completion: Hashable, Codable {

    /// Capabilities specific to `CompletionItem`.
    public struct CompletionItem: Hashable, Codable {

      /// Whether the client supports rich snippets using placeholders, etc.
      public var snippetSupport: Bool? = nil

      /// Whether the client supports commit characters on a CompletionItem.
      public var commitCharactersSupport: Bool? = nil

      /// Documentation formats supported by the client from most to least preferred.
      public var documentationFormat: [MarkupKind]? = nil

      /// Whether the client supports the `deprecated` property on a CompletionItem.
      public var deprecatedSupport: Bool? = nil

      /// Whether the client supports the `preselect` property on a CompletionItem.
      public var preselectSupport: Bool? = nil

      public init(
        snippetSupport: Bool? = nil,
        commitCharactersSupport: Bool? = nil,
        documentationFormat: [MarkupKind]? = nil,
        deprecatedSupport: Bool? = nil,
        preselectSupport: Bool? = nil
      ) {
        self.snippetSupport = snippetSupport
        self.commitCharactersSupport = commitCharactersSupport
        self.documentationFormat = documentationFormat
        self.deprecatedSupport = deprecatedSupport
        self.preselectSupport = preselectSupport
      }
    }

    /// Capabilities specific to `CompletionItemKind`.
    public struct CompletionItemKind: Hashable, Codable {

      /// The completion kind values that the client can support.
      ///
      /// If not specified, the client support only the kinds from `Text` to `Reference` from LSP 1.
      ///
      /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
      public var valueSet: [LanguageServerProtocol.CompletionItemKind]? = nil

      public init(valueSet: [LanguageServerProtocol.CompletionItemKind]? = nil) {
        self.valueSet = valueSet
      }
    }

    // MARK: Properties

    /// Whether the client supports dynamic registaration of these capabilities.
    public var dynamicRegistration: Bool? = nil

    public var completionItem: CompletionItem? = nil

    public var completionItemKind: CompletionItemKind? = nil

    /// Whether the client supports sending context information in a `textDocument/completion` request.
    public var contextSupport: Bool? = nil

    public init(
      dynamicRegistration: Bool? = nil,
      completionItem: CompletionItem? = nil,
      completionItemKind: CompletionItemKind? = nil,
      contextSupport: Bool? = nil
    ) {
      self.dynamicRegistration = dynamicRegistration
      self.completionItem = completionItem
      self.completionItemKind = completionItemKind
      self.contextSupport = contextSupport
    }
  }

  /// Capabilities specific to the `textDocument/hover` request.
  public struct Hover: Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Formats supported by the client for the `Hover.content` property from most to least preferred.
    public var contentFormat: [MarkupKind]? = nil

    public init(dynamicRegistration: Bool? = nil, contentFormat: [MarkupKind]? = nil) {
      self.dynamicRegistration = dynamicRegistration
      self.contentFormat = contentFormat
    }
  }

  /// Capabilities specific to the `textDocument/signatureHelp` request.
  public struct SignatureHelp: Hashable, Codable {

    /// Capabilities specific to `SignatureInformation`.
    public struct SignatureInformation: Hashable, Codable {
      public struct ParameterInformation: Hashable, Codable {
        /// The client supports processing label offsets instead of a simple label string.
        var labelOffsetSupport: Bool? = nil

        public init(labelOffsetSupport: Bool? = nil) {
          self.labelOffsetSupport = labelOffsetSupport
        }
      }

      /// Documentation formats supported by the client from most to least preferred.
      public var documentationFormat: [MarkupKind]? = nil

      public var parameterInformation: ParameterInformation? = nil

      public init(signatureInformation: [MarkupKind]? = nil, parameterInformation: ParameterInformation? = nil) {
        self.documentationFormat = signatureInformation
        self.parameterInformation = parameterInformation
      }
    }

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    public var signatureInformation: SignatureInformation? = nil

    public init(dynamicRegistration: Bool? = nil, signatureInformation: SignatureInformation? = nil) {
      self.dynamicRegistration = dynamicRegistration
      self.signatureInformation = signatureInformation
    }
  }

  /// Capabilities specific to the `textDocument/documentSymbol` request.
  public struct DocumentSymbol: Hashable, Codable {

    /// Capabilities specific to `SymbolKind`.
    public struct SymbolKind: Hashable, Codable {

      /// The symbol kind values that the client can support.
      ///
      /// If not specified, the client support only the kinds from `File` to `Array` from LSP 1.
      ///
      /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
      public var valueSet: [LanguageServerProtocol.SymbolKind]? = nil

      public init(valueSet: [LanguageServerProtocol.SymbolKind]? = nil) {
        self.valueSet = valueSet
      }
    }

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    public var symbolKind: SymbolKind? = nil

    public var hierarchicalDocumentSymbolSupport: Bool? = nil

    public init(
      dynamicRegistration: Bool? = nil,
      symbolKind: SymbolKind? = nil,
      hierarchicalDocumentSymbolSupport: Bool? = nil
    ) {
      self.dynamicRegistration = dynamicRegistration
      self.symbolKind = symbolKind
      self.hierarchicalDocumentSymbolSupport = hierarchicalDocumentSymbolSupport
    }
  }

  public struct DynamicRegistrationLinkSupportCapability: Hashable, Codable {
    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// The client supports additional metadata in the form of declaration links.
    public var linkSupport: Bool? = nil

    public init(dynamicRegistration: Bool? = nil, linkSupport: Bool? = nil) {
      self.dynamicRegistration = dynamicRegistration
      self.linkSupport = linkSupport
    }
  }

  /// Capabilities specific to the `textDocument/codeAction` request.
  public struct CodeAction: Hashable, Codable {

    /// Liteals accepted by the client in response to a `textDocument/codeAction` request.
    public struct CodeActionLiteralSupport: Hashable, Codable {
      /// Accepted code action kinds.
      public struct CodeActionKind: Hashable, Codable {

        /// The code action kind values that the client can support.
        ///
        /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
        public var valueSet: [LanguageServerProtocol.CodeActionKind]

        public init(valueSet: [LanguageServerProtocol.CodeActionKind]) {
          self.valueSet = valueSet
        }
      }

      public var codeActionKind: CodeActionKind

      public init(codeActionKind: CodeActionKind) {
        self.codeActionKind = codeActionKind
      }
    }

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool?

    public var codeActionLiteralSupport: CodeActionLiteralSupport? = nil

    public init(dynamicRegistration: Bool? = nil, codeActionLiteralSupport: CodeActionLiteralSupport? = nil) {
      self.codeActionLiteralSupport = codeActionLiteralSupport
    }
  }

  /// Capabilities specific to `textDocument/rename`.
  public struct Rename: Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool?

    /// The client supports testing for validity of rename operations before execution.
    public var prepareSupport: Bool?

    public init(dynamicRegistration: Bool? = nil, prepareSupport: Bool? = nil) {
      self.dynamicRegistration = dynamicRegistration
      self.prepareSupport = prepareSupport
    }
  }

  /// Capabilities specific to `textDocument/publishDiagnostics`.
  public struct PublishDiagnostics: Hashable, Codable {
    /// Whether the client accepts diagnostics with related information.
    public var relatedInformation: Bool? = nil

    /// Requests that SourceKit-LSP send `Diagnostic.codeActions`.
    /// **LSP Extension from clangd**.
    public var codeActionsInline: Bool? = nil

    /// Whether the client supports a `codeDescription` property.
    public var codeDescriptionSupport: Bool? = nil

    public init(
      relatedInformation: Bool? = nil,
      codeActionsInline: Bool? = nil,
      codeDescriptionSupport: Bool? = nil
    ) {
      self.relatedInformation = relatedInformation
      self.codeActionsInline = codeActionsInline
      self.codeDescriptionSupport = codeDescriptionSupport
    }
  }

  /// Capabilities specific to `textDocument/foldingRange`.
  public struct FoldingRange: Equatable, Hashable, Codable {

    /// Whether the client supports dynamic registration of this request.
    public var dynamicRegistration: Bool? = nil

    /// The maximum number of folding ranges that the client prefers to receive per document.
    public var rangeLimit: Int? = nil

    /// If set, the client signals that it only supports folding complete lines. If set, client will
    /// ignore specified `startUTF16Index` and `endUTF16Index` properties in a FoldingRange.
    public var lineFoldingOnly: Bool? = nil

    public init(dynamicRegistration: Bool? = nil, rangeLimit: Int? = nil, lineFoldingOnly: Bool? = nil) {
      self.dynamicRegistration = dynamicRegistration
      self.rangeLimit = rangeLimit
      self.lineFoldingOnly = lineFoldingOnly
    }
  }

  public struct SemanticTokensRangeClientCapabilities: Equatable, Hashable, Codable {
    // Empty in the LSP 3.16 spec.
    public init() {}
  }

  public struct SemanticTokensFullClientCapabilities: Equatable, Hashable, Codable {
    /// The client will also send the `textDocument/semanticTokens/full/delta`
    /// request if the server provides a corresponding handler.
    public var delta: Bool?

    public init(delta: Bool? = nil) {
      self.delta = delta
    }
  }

  public struct SemanticTokensRequestsClientCapabilities: Equatable, Hashable, Codable {
    /// The client will send the `textDocument/semanticTokens/range` request
    /// if the server provides a corresponding handler.
    public var range: ValueOrBool<SemanticTokensRangeClientCapabilities>?

    /// The client will send the `textDocument/semanticTokens/full` request
    /// if the server provides a corresponding handler.
    public var full: ValueOrBool<SemanticTokensFullClientCapabilities>?

    public init(
      range: ValueOrBool<SemanticTokensRangeClientCapabilities>?,
      full: ValueOrBool<SemanticTokensFullClientCapabilities>?
    ) {
      self.range = range
      self.full = full
    }
  }

  /// Capabilities specific to `textDocument/semanticTokens`.
  public struct SemanticTokens: Equatable, Hashable, Codable {

    /// Whether the client supports dynamic registration of this request.
    public var dynamicRegistration: Bool? = nil

    public var requests: SemanticTokensRequestsClientCapabilities

    /// The token types that the client supports.
    public var tokenTypes: [String]

    /// The token modifiers that the client supports.
    public var tokenModifiers: [String]

    /// The formats the clients supports.
    public var formats: [TokenFormat]

    /// Whether the client supports tokens that can overlap each other.
    public var overlappingTokenSupport: Bool? = nil

    /// Whether the client supports tokens that can span multiple lines.
    public var multilineTokenSupport: Bool? = nil

    public init(
      dynamicRegistration: Bool? = nil,
      requests: SemanticTokensRequestsClientCapabilities,
      tokenTypes: [String],
      tokenModifiers: [String],
      formats: [TokenFormat],
      overlappingTokenSupport: Bool? = nil,
      multilineTokenSupport: Bool? = nil
    ) {
      self.dynamicRegistration = dynamicRegistration
      self.requests = requests
      self.tokenTypes = tokenTypes
      self.tokenModifiers = tokenModifiers
      self.formats = formats
      self.overlappingTokenSupport = overlappingTokenSupport
      self.multilineTokenSupport = multilineTokenSupport
    }
  }

  /// Capabilities specific to 'textDocument/inlayHint'.
  public struct InlayHint: Hashable, Codable {
    /// Properties a client can resolve lazily.
    public struct ResolveSupport: Hashable, Codable {
      /// The properties that a client can resolve lazily.
      public var properties: [String]

      public init(properties: [String] = []) {
        self.properties = properties
      }
    }

    /// Whether inlay hints support dynamic registration.
    public var dynamicRegistration: Bool?

    /// Indicates which properties a client can resolve lazily on an inlay hint.
    public var resolveSupport: ResolveSupport?

    public init(
      dynamicRegistration: Bool? = nil,
      resolveSupport: ResolveSupport? = nil
    ) {
      self.dynamicRegistration = dynamicRegistration
      self.resolveSupport = resolveSupport
    }
  }

  /// Capabilities specific to 'textDocument/diagnostic'. Since LSP 3.17.0.
  public struct Diagnostic: Equatable, Hashable, Codable {

    /// Whether implementation supports dynamic registration.
    public var dynamicRegistration: Bool?

    /// Whether the clients supports related documents for document diagnostic pulls.
    public var relatedDocumentSupport: Bool?
  }

  // MARK: Properties

  public var synchronization: Synchronization? = nil

  public var completion: Completion? = nil

  public var hover: Hover? = nil

  public var signatureHelp: SignatureHelp? = nil

  public var declaration: DynamicRegistrationLinkSupportCapability? = nil

  public var definition: DynamicRegistrationLinkSupportCapability? = nil

  public var typeDefinition: DynamicRegistrationLinkSupportCapability? = nil

  public var implementation: DynamicRegistrationLinkSupportCapability? = nil

  public var references: DynamicRegistrationCapability? = nil

  public var documentHighlight: DynamicRegistrationCapability? = nil

  public var documentSymbol: DocumentSymbol? = nil

  public var codeAction: CodeAction? = nil

  public var codeLens: DynamicRegistrationCapability? = nil

  public var documentLink: DynamicRegistrationCapability? = nil

  public var colorProvider: DynamicRegistrationCapability? = nil

  public var formatting: DynamicRegistrationCapability? = nil

  public var rangeFormatting: DynamicRegistrationCapability? = nil

  public var onTypeFormatting: DynamicRegistrationCapability? = nil

  public var rename: DynamicRegistrationCapability? = nil

  public var publishDiagnostics: PublishDiagnostics? = nil

  public var foldingRange: FoldingRange? = nil

  public var selectionRange: DynamicRegistrationCapability? = nil

  public var linkedEditingRange: DynamicRegistrationCapability? = nil

  public var callHierarchy: DynamicRegistrationCapability? = nil

  public var semanticTokens: SemanticTokens? = nil

  public var moniker: DynamicRegistrationCapability? = nil

  public var typeHierarchy: DynamicRegistrationCapability? = nil

  public var inlineValue: DynamicRegistrationCapability? = nil

  public var inlayHint: InlayHint? = nil

  public var diagnostic: Diagnostic? = nil

  public init(
    synchronization: Synchronization? = nil,
    completion: Completion? = nil,
    hover: Hover? = nil,
    signatureHelp: SignatureHelp? = nil,
    declaration: DynamicRegistrationLinkSupportCapability? = nil,
    definition: DynamicRegistrationLinkSupportCapability? = nil,
    typeDefinition: DynamicRegistrationLinkSupportCapability? = nil,
    implementation: DynamicRegistrationLinkSupportCapability? = nil,
    references: DynamicRegistrationCapability? = nil,
    documentHighlight: DynamicRegistrationCapability? = nil,
    documentSymbol: DocumentSymbol? = nil,
    codeAction: CodeAction? = nil,
    codeLens: DynamicRegistrationCapability? = nil,
    documentLink: DynamicRegistrationCapability? = nil,
    colorProvider: DynamicRegistrationCapability? = nil,
    formatting: DynamicRegistrationCapability? = nil,
    rangeFormatting: DynamicRegistrationCapability? = nil,
    onTypeFormatting: DynamicRegistrationCapability? = nil,
    rename: DynamicRegistrationCapability? = nil,
    publishDiagnostics: PublishDiagnostics? = nil,
    foldingRange: FoldingRange? = nil,
    selectionRange: DynamicRegistrationCapability? = nil,
    linkedEditingRange: DynamicRegistrationCapability? = nil,
    callHierarchy: DynamicRegistrationCapability? = nil,
    semanticTokens: SemanticTokens? = nil,
    moniker: DynamicRegistrationCapability? = nil,
    typeHierarchy: DynamicRegistrationCapability? = nil,
    inlineValue: DynamicRegistrationCapability? = nil,
    inlayHint: InlayHint? = nil,
    diagnostic: Diagnostic? = nil
  ) {
    self.synchronization = synchronization
    self.completion = completion
    self.hover = hover
    self.signatureHelp = signatureHelp
    self.declaration = declaration
    self.definition = definition
    self.typeDefinition = typeDefinition
    self.implementation = implementation
    self.references = references
    self.documentHighlight = documentHighlight
    self.documentSymbol = documentSymbol
    self.codeAction = codeAction
    self.codeLens = codeLens
    self.documentLink = documentLink
    self.colorProvider = colorProvider
    self.formatting = formatting
    self.rangeFormatting = rangeFormatting
    self.onTypeFormatting = onTypeFormatting
    self.rename = rename
    self.publishDiagnostics = publishDiagnostics
    self.foldingRange = foldingRange
    self.selectionRange = selectionRange
    self.linkedEditingRange = linkedEditingRange
    self.callHierarchy = callHierarchy
    self.semanticTokens = semanticTokens
    self.moniker = moniker
    self.typeHierarchy = typeHierarchy
    self.inlineValue = inlineValue
    self.inlayHint = inlayHint
    self.diagnostic = diagnostic
  }
}

/// Capabilities specific to the notebook document support.
public struct NotebookDocumentClientCapabilities: Hashable, Codable {
  public struct NotebookDocumentSync: Hashable, Codable {
    /// Whether implementation supports dynamic registration. If this is
    /// set to `true` the client supports the new
    /// `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
    /// return value for the corresponding server capability as well.
    public var dynamicRegistration: Bool?

    /// The client supports sending execution summary data per cell.
    public var executionSummarySupport: Bool?

    public init(
      dynamicRegistration: Bool?,
      executionSummarySupport: Bool?
    ) {
      self.dynamicRegistration = dynamicRegistration
      self.executionSummarySupport = executionSummarySupport
    }
  }

  /// Capabilities specific to notebook document synchronization
  public var synchronization: NotebookDocumentSync

  public init(synchronization: NotebookDocumentSync) {
    self.synchronization = synchronization
  }
}

/// Window specific client capabilities.
public struct WindowClientCapabilities: Hashable, Codable {
  /// Show message request client capabilities
  public struct ShowMessageRequest: Hashable, Codable {
    public struct MessageActionItem: Hashable, Codable {
      /// Whether the client supports additional attributes which
      /// are preserved and sent back to the server in the
      /// request's response.
      public var additionalPropertiesSupport: Bool?

      public init(additionalPropertiesSupport: Bool? = nil) {
        self.additionalPropertiesSupport = additionalPropertiesSupport
      }
    }

    /// Capabilities specific to the `MessageActionItem` type.
    public var messageActionItem: MessageActionItem?

    public init(messageActionItem: MessageActionItem? = nil) {
      self.messageActionItem = messageActionItem
    }
  }

  /// Client capabilities for the show document request.
  public struct ShowDocument: Hashable, Codable {
    /// The client has support for the show document
    /// request.
    public var support: Bool

    public init(support: Bool) {
      self.support = support
    }
  }

  /// It indicates whether the client supports server initiated
  /// progress using the `window/workDoneProgress/create` request.
  ///
  /// The capability also controls Whether client supports handling
  /// of progress notifications. If set servers are allowed to report a
  /// `workDoneProgress` property in the request specific server
  /// capabilities.
  public var workDoneProgress: Bool?

  /// Capabilities specific to the showMessage request
  public var showMessage: ShowMessageRequest?

  public var showDocument: ShowDocument?

  public init(
    workDoneProgress: Bool? = nil,
    showMessage: ShowMessageRequest? = nil,
    showDocument: ShowDocument? = nil
  ) {
    self.workDoneProgress = workDoneProgress
    self.showMessage = showMessage
    self.showDocument = showDocument
  }
}

/// General client capabilities.
public struct GeneralClientCapabilities: Hashable, Codable {
  public struct StaleRequestSupport: Hashable, Codable {
    /// The client will actively cancel the request.
    public var cancel: Bool

    /// The list of requests for which the client
    /// will retry the request if it receives a
    /// response with error code `ContentModified``
    public var retryOnContentModified: [String]

    public init(cancel: Bool, retryOnContentModified: [String]) {
      self.cancel = cancel
      self.retryOnContentModified = retryOnContentModified
    }
  }

  /// Client capabilities specific to regular expressions.
  public struct RegularExpressions: Hashable, Codable {
    /// The engine's name.
    public var engine: String

    /// The engine's version.
    public var version: String?

    public init(engine: String, version: String? = nil) {
      self.engine = engine
      self.version = version
    }
  }

  /// Client capabilities specific to the used markdown parser.
  public struct Markdown: Hashable, Codable {
    /// The name of the parser.
    public var parser: String

    /// The version of the parser.
    public var version: String?

    /// A list of HTML tags that the client allows / supports in Markdown.
    public var allowedTags: [String]?

    public init(parser: String, version: String? = nil, allowedTags: [String]? = nil) {
      self.parser = parser
      self.version = version
      self.allowedTags = allowedTags
    }
  }

  /// A type indicating how positions are encoded,
  /// specifically what column offsets mean.
  public enum PositionEncodingKind: String, Hashable, Codable {

    /// Character offsets count UTF-8 code units (e.g bytes).
    case utf8 = "utf-8"

    /// Character offsets count UTF-16 code units.
    ///
    /// This is the default and must always be supported
    /// by servers
    case utf16 = "utf-16"

    /// Character offsets count UTF-32 code units.
    ///
    /// Implementation note: these are the same as Unicode code points,
    /// so this `PositionEncodingKind` may also be used for an
    /// encoding-agnostic representation of character offsets.
    case utf32 = "utf-32"
  }

  /// Client capability that signals how the client
  /// handles stale requests (e.g. a request
  /// for which the client will not process the response
  /// anymore since the information is outdated).
  public var staleRequestSupport: StaleRequestSupport?

  /// Client capabilities specific to regular expressions.
  public var regularExpressions: RegularExpressions?

  /// Client capabilities specific to the client's markdown parser.
  public var markdown: Markdown?

  /// The position encodings supported by the client. Client and server
  /// have to agree on the same position encoding to ensure that offsets
  /// (e.g. character position in a line) are interpreted the same on both
  /// side.
  ///
  /// To keep the protocol backwards compatible the following applies: if
  /// the value 'utf-16' is missing from the array of position encodings
  /// servers can assume that the client supports UTF-16. UTF-16 is
  /// therefore a mandatory encoding.
  ///
  /// If omitted it defaults to ['utf-16'].
  ///
  /// Implementation considerations: since the conversion from one encoding
  /// into another requires the content of the file / line the conversion
  /// is best done where the file is read which is usually on the server
  /// side.
  public var positionEncodings: [PositionEncodingKind]?

  public init(
    staleRequestSupport: StaleRequestSupport? = nil,
    regularExpressions: RegularExpressions? = nil,
    markdown: Markdown? = nil,
    positionEncodings: [PositionEncodingKind]? = nil
  ) {
    self.staleRequestSupport = staleRequestSupport
    self.regularExpressions = regularExpressions
    self.markdown = markdown
    self.positionEncodings = positionEncodings
  }
}
