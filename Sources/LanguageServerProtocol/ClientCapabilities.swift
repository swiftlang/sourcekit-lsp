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
public struct ClientCapabilities {

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

extension ClientCapabilities: Equatable {}
extension ClientCapabilities: Hashable {}
extension ClientCapabilities: Codable {}

/// Helper capability wrapper for structs that only have a `dynamicRegistration` member.
public struct DynamicRegistrationCapability {
  /// Whether the client supports dynamic registaration of this feature.
  public var dynamicRegistration: Bool? = nil
}

extension DynamicRegistrationCapability: Equatable {}
extension DynamicRegistrationCapability: Hashable {}
extension DynamicRegistrationCapability: Codable {}

/// Capabilities of the client editor/IDE related to managing the workspace.
// FIXME: Instead of making all of these optional, provide default values and make the deserialization handle missing values.
public struct WorkspaceClientCapabilities {

  /// Capabilities specific to `WorkspaceEdit`.
  public struct WorkspaceEdit: Equatable, Hashable, Codable {
    /// Whether the client supports the `documentChanges` field of `WorkspaceEdit`.
    public var documentChanges: Bool? = nil

    public init(documentChanges: Bool? = nil) {
      self.documentChanges = documentChanges
    }
  }

  /// Capabilities specific to the `workspace/symbol` request.
  public struct Symbol: Equatable, Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Capabilities specific to `SymbolKind`.
    public struct SymbolKind: Equatable, Hashable, Codable {

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

extension WorkspaceClientCapabilities: Equatable {}
extension WorkspaceClientCapabilities: Hashable {}
extension WorkspaceClientCapabilities: Codable {}

/// Capabilities of the client editor/IDE related to the document.
// FIXME: Instead of making all of these optional, provide default values and make the deserialization handle missing values.
public struct TextDocumentClientCapabilities {

  /// Capabilities specific to the `textDocument/...` change notifications.
  public struct Synchronization: Equatable, Hashable, Codable {

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
  public struct Completion: Equatable, Hashable, Codable {

    /// Capabilities specific to `CompletionItem`.
    public struct CompletionItem: Equatable, Hashable, Codable {

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
    public struct CompletionItemKind: Equatable, Hashable, Codable {

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
  public struct Hover: Equatable, Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Formats supported by the client for the `Hover.content` property from most to least preferred.
    public var contentFormat: [MarkupKind]? = nil
  }

  /// Capabilities specific to the `textDocument/signatureHelp` request.
  public struct SignatureHelp: Equatable, Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Capabilities specific to `SignatureInformation`.
    public struct SignatureInformation: Equatable, Hashable, Codable {
      /// Documentation formats supported by the client from most to least preferred.
      public var signatureInformation: [MarkupKind]? = nil
    }

    public var signatureInformation: SignatureInformation? = nil
  }

  /// Capabilities specific to the `textDocument/documentSymbol` request.
  public struct DocumentSymbol: Equatable, Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Capabilities specific to `SignatureInformation`.
    public struct SymbolKind: Equatable, Hashable, Codable {

      /// The symbol kind values that the client can support.
      ///
      /// If not specified, the client support only the kinds from `File` to `Array` from LSP 1.
      ///
      /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
      public var valueSet: [LanguageServerProtocol.SymbolKind]? = nil
    }

    public var symbolKind: SymbolKind? = nil
  }

  /// Capabilities specific to the `textDocument/codeAction` request.
  public struct CodeAction: Equatable, Hashable, Codable {

    /// Whether the client supports dynamic registaration of this request.
    public var dynamicRegistration: Bool? = nil

    /// Liteals accepted by the client in response to a `textDocument/codeAction` request.
    public struct CodeActionLiteralSupport: Equatable, Hashable, Codable {
      /// Accepted code action kinds.
      public struct CodeActionKind: Equatable, Hashable, Codable {

        /// The code action kind values that the client can support.
        ///
        /// If specified, the client *also* guarantees that it will handle unknown kinds gracefully.
        public var valueSet: [LanguageServerProtocol.CodeActionKind]? = nil
      }

      public var codeActionKind: CodeActionKind? = nil
    }

    public var codeActionLiteralSupport: CodeActionLiteralSupport? = nil
  }

  /// Capabilities specific to `textDocument/publishDiagnostics`.
  public struct PublishDiagnostics: Equatable, Hashable, Codable {
    /// Whether the client accepts diagnostics with related information.
    public var relatedInformation: Bool? = nil
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
}

extension TextDocumentClientCapabilities: Equatable {}
extension TextDocumentClientCapabilities: Hashable {}
extension TextDocumentClientCapabilities: Codable {}
