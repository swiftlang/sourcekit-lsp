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

  // FIXME: public var experimental: Any?

  public init(workspace: WorkspaceClientCapabilities? = nil, textDocument: TextDocumentClientCapabilities? = nil) {
    self.workspace = workspace
    self.textDocument = textDocument
  }
}

/// Helper capability wrapper for structs that only have a `dynamicRegistration` member.
public struct DynamicRegistrationCapability: Hashable, Codable {
  /// Whether the client supports dynamic registaration of this feature.
  public var dynamicRegistration: Bool? = nil
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

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Capabilities specific to `SymbolKind`.
    public struct SymbolKind: Hashable, Codable {

      /// The symbol kind values that the client can support.
      ///
      /// If not specified, the client support only the kinds from `File` to `Array` from LSP 1.
      ///
      /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
      public var valueSet: [LanguageServerProtocol.SymbolKind]? = nil
    }

    public var symbolKind: SymbolKind? = nil
  }

  // MARK: Properties

  /// Whether the client can apply text edits via the `workspace/applyEdit` request.
  public var applyEdit: Bool? = nil

  public var workspaceEdit: WorkspaceEdit? = nil

  public var didChangeConfiguration: DynamicRegistrationCapability? = nil

  public var didChangeWatchedFiles: DynamicRegistrationCapability? = nil

  public var symbol: Symbol? = nil

  public var executeCommand: DynamicRegistrationCapability? = nil

  /// Whether the client supports workspace folders.
  public var workspaceFolders: Bool? = nil

  /// Whether the client supports the `workspace/configuration` request.
  public var configuration: Bool? = nil

  public init() {
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
    }

    /// Capabilities specific to `CompletionItemKind`.
    public struct CompletionItemKind: Hashable, Codable {

      /// The completion kind values that the client can support.
      ///
      /// If not specified, the client support only the kinds from `Text` to `Reference` from LSP 1.
      ///
      /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
      public var valueSet: [LanguageServerProtocol.CompletionItemKind]? = nil
    }

    // MARK: Properties

    /// Whether the client supports dynamic registaration of these capabilities.
    public var dynamicRegistration: Bool? = nil

    public var completionItem: CompletionItem? = nil

    public var completionItemKind: CompletionItemKind? = nil

    /// Whether the client supports sending context information in a `textDocument/completion` request.
    public var contextSupport: Bool? = nil
  }

  /// Capabilities specific to the `textDocument/hover` request.
  public struct Hover: Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Formats supported by the client for the `Hover.content` property from most to least preferred.
    public var contentFormat: [MarkupKind]? = nil
  }

  /// Capabilities specific to the `textDocument/signatureHelp` request.
  public struct SignatureHelp: Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Capabilities specific to `SignatureInformation`.
    public struct SignatureInformation: Hashable, Codable {
      /// Documentation formats supported by the client from most to least preferred.
      public var signatureInformation: [MarkupKind]? = nil
    }

    public var signatureInformation: SignatureInformation? = nil
  }

  /// Capabilities specific to the `textDocument/documentSymbol` request.
  public struct DocumentSymbol: Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Capabilities specific to `SymbolKind`.
    public struct SymbolKind: Hashable, Codable {

      /// The symbol kind values that the client can support.
      ///
      /// If not specified, the client support only the kinds from `File` to `Array` from LSP 1.
      ///
      /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
      public var valueSet: [LanguageServerProtocol.SymbolKind]? = nil
    }

    public var symbolKind: SymbolKind? = nil

    public init() {
    }
  }

  /// Capabilities specific to the `textDocument/codeAction` request.
  public struct CodeAction: Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Liteals accepted by the client in response to a `textDocument/codeAction` request.
    public struct CodeActionLiteralSupport: Hashable, Codable {
      /// Accepted code action kinds.
      public struct CodeActionKind: Hashable, Codable {

        /// The code action kind values that the client can support.
        ///
        /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
        public var valueSet: [LanguageServerProtocol.CodeActionKind]
      }

      public var codeActionKind: CodeActionKind
    }

    public var codeActionLiteralSupport: CodeActionLiteralSupport? = nil
  }

  /// Capabilities specific to `textDocument/publishDiagnostics`.
  public struct PublishDiagnostics: Hashable, Codable {
    /// Whether the client accepts diagnostics with related information.
    public var relatedInformation: Bool? = nil
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

    public init() {
    }
  }

  // MARK: Properties

  public var synchronization: Synchronization? = nil

  public var completion: Completion? = nil

  public var hover: Hover? = nil

  public var signatureHelp: SignatureHelp? = nil

  public var references: DynamicRegistrationCapability? = nil

  public var documentHighlight: DynamicRegistrationCapability? = nil

  public var documentSymbol: DocumentSymbol? = nil

  public var formatting: DynamicRegistrationCapability? = nil

  public var rangeFormatting: DynamicRegistrationCapability? = nil

  public var onTypeFormatting: DynamicRegistrationCapability? = nil

  public var definition: DynamicRegistrationCapability? = nil

  public var typeDefinition: DynamicRegistrationCapability? = nil

  public var implementation: DynamicRegistrationCapability? = nil

  public var codeAction: CodeAction? = nil

  public var codeLens: DynamicRegistrationCapability? = nil

  public var documentLink: DynamicRegistrationCapability? = nil

  public var colorProvider: DynamicRegistrationCapability? = nil

  public var rename: DynamicRegistrationCapability? = nil

  public var publishDiagnostics: PublishDiagnostics? = nil

  public var foldingRange: FoldingRange? = nil

  public init() {
  }
}
