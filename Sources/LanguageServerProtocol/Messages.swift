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

import Basic

/// The set of known requests.
///
/// All requests from LSP as well as any extensions provided by the server should be listed here. If you are adding a message for testing only, you can register it dynamically using `MessageRegistry._register()` which allows you to avoid bloating the real server implementation.
public let builtinRequests: [_RequestType.Type] = [
  InitializeRequest.self,
  Shutdown.self,
  WorkspaceFoldersRequest.self,
  CompletionRequest.self,
  HoverRequest.self,
  DefinitionRequest.self,
  ReferencesRequest.self,
  DocumentHighlightRequest.self,
  DocumentFormatting.self,
  DocumentRangeFormatting.self,
  DocumentOnTypeFormatting.self,

  // MARK: LSP Extension Requests

  SymbolInfoRequest.self,
]

/// The set of known notifications.
///
/// All notifications from LSP as well as any extensions provided by the server should be listed here. If you are adding a message for testing only, you can register it dynamically using `MessageRegistry._register()` which allows you to avoid bloating the real server implementation.
public let builtinNotifications: [NotificationType.Type] = [
  InitializedNotification.self,
  Exit.self,
  CancelRequest.self,
  LogMessage.self,
  DidChangeConfiguration.self,
  DidChangeWorkspaceFolders.self,
  DidOpenTextDocument.self,
  DidCloseTextDocument.self,
  DidChangeTextDocument.self,
  DidSaveTextDocument.self,
  WillSaveTextDocument.self,
  PublishDiagnostics.self,
]

// MARK: - General -

public struct InitializeRequest: RequestType, Hashable {
  public static let method: String = "initialize"
  public typealias Response = InitializeResult

  /// The process identifier (pid) of the process that started the LSP server, or nil if the server was started by e.g. a user shell and should not be monitored.
  ///
  /// If the client process dies, the server should exit.
  public var processId: Int? = nil

  /// The workspace path, or nil if no workspace is open.
  ///
  /// - Note: deprecated in favour of `rootURL`.
  public var rootPath: String? = nil

  /// The workspace URL, or nil if no workspace is open.
  ///
  /// Takes precedence over the deprecated `rootPath`.
  public var rootURL: URL?

  /// Any user-provided options.
  public var initializationOptions: InitializationOptions? = nil

  /// The capabilities provided by the client editor.
  public var capabilities: ClientCapabilities

  public enum Tracing: String, Codable  {
    case off
    case messages
    case verbose
  }

  /// Whether to enable tracing.
  public var trace: Tracing? = .off

  /// The workspace folders configued, if the client supports multiple workspace folders.
  public var workspaceFolders: [WorkspaceFolder]?

  public init(processId: Int? = nil, rootPath: String? = nil, rootURL: URL?, initializationOptions: InitializationOptions? = nil, capabilities: ClientCapabilities, trace: Tracing = .off, workspaceFolders: [WorkspaceFolder]?) {
    self.processId = processId
    self.rootPath = rootPath
    self.rootURL = rootURL
    self.initializationOptions = initializationOptions
    self.capabilities = capabilities
    self.trace = trace
    self.workspaceFolders = workspaceFolders
  }
}

extension InitializeRequest: Codable {
  private enum CodingKeys: String, CodingKey {
    case processId
    case rootPath
    case rootURL = "rootUri"
    case initializationOptions
    case capabilities
    case trace
    case workspaceFolders
  }
}

public struct InitializeResult: ResponseType, Hashable {

  /// The capabilities of the language server.
  public var capabilities: ServerCapabilities

  public init(capabilities: ServerCapabilities) {
    self.capabilities = capabilities
  }
}

public struct InitializedNotification: NotificationType, Hashable {
  public static let method: String = "initialized"

  public init() {}
}

public struct CancelRequest: NotificationType, Hashable {
  public static let method: String = "$/cancelRequest"

  /// The request to cancel.
  public var id: RequestID

  public init(id: RequestID) {
    self.id = id
  }
}

public struct VoidResponse: ResponseType, Hashable {
  public init() {}
}

extension Optional: MessageType where Wrapped: MessageType {}
extension Optional: ResponseType where Wrapped: ResponseType {}

extension Array: MessageType where Element: MessageType {}
extension Array: ResponseType where Element: ResponseType {}

extension Location: ResponseType {}

public struct Shutdown: RequestType, Hashable {
  public static let method: String = "shutdown"
  public typealias Response = VoidResponse
}

public struct Exit: NotificationType, Hashable {
  public static let method: String = "exit"
}

// MARK: - Window -

public struct LogMessage: NotificationType, Hashable {
  public static let method: String = "window/logMessage"

  public var type: WindowMessageType

  public var message: String

  public init(type: WindowMessageType, message: String) {
    self.type = type
    self.message = message
  }
}

// MARK: - Workspace -

public struct WorkspaceFoldersRequest: RequestType, Hashable {
    public static let method: String = "workspace/workspaceFolders"

    public typealias Response = [WorkspaceFolder]
}

public struct DidChangeConfiguration: NotificationType {
  public static let method: String = "workspace/didChangeConfiguration"

  public var settings: WorkspaceSettingsChange

  public init(settings: WorkspaceSettingsChange) {
    self.settings = settings
  }
}

public struct DidChangeWorkspaceFolders: NotificationType {
    public static let method: String = "workspace/didChangeWorkspaceFolders"

    public var event: WorkspaceFoldersChangeEvent

    public init(event: WorkspaceFoldersChangeEvent) {
        self.event = event
    }
}

// MARK: - Text synchronization -

public struct DidOpenTextDocument: NotificationType, Hashable {
  public static let method: String = "textDocument/didOpen"

  public var textDocument: TextDocumentItem

  public init(textDocument: TextDocumentItem) {
    self.textDocument = textDocument
  }
}

public struct DidCloseTextDocument: NotificationType, Hashable {
  public static let method: String = "textDocument/didClose"

  public var textDocument: TextDocumentIdentifier
}

public struct DidChangeTextDocument: NotificationType, Hashable {
  public static let method: String = "textDocument/didChange"

  public var textDocument: VersionedTextDocumentIdentifier

  public var contentChanges: [TextDocumentContentChangeEvent]

  public init(textDocument: VersionedTextDocumentIdentifier, contentChanges: [TextDocumentContentChangeEvent]) {
    self.textDocument = textDocument
    self.contentChanges = contentChanges
  }
}

public struct WillSaveTextDocument: NotificationType, Hashable {
  public static let method: String = "textDocument/willSave"

  public var textDocument: TextDocumentIdentifier

  public var reason: TextDocumentSaveReason
}

public struct DidSaveTextDocument: NotificationType, Hashable {
  public static let method: String = "textDocument/didSave"

  public var textDocument: TextDocumentIdentifier

  /// The content of the file.
  ///
  /// - note: Only provided if the server specified `includeText == true`.
  public var text: String?
}

// MARK: - Diagnostics -

public struct PublishDiagnostics: NotificationType, Hashable {
  public static let method: String = "textDocument/publishDiagnostics"

  public var url: URL

  public var diagnostics: [Diagnostic]

  public init(url: URL, diagnostics: [Diagnostic]) {
    self.url = url
    self.diagnostics = diagnostics
  }
}

extension PublishDiagnostics: Codable {
  private enum CodingKeys: String, CodingKey {
    case url = "uri"
    case diagnostics
  }
}

// MARK: - Language features -

public protocol TextDocumentRequest: RequestType {

  var textDocument: TextDocumentIdentifier { get }
}

public struct CompletionRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/completion"
  public typealias Response = CompletionList

  public var textDocument: TextDocumentIdentifier

  public var position: Position

  // public var context: CompletionContext?

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

public struct CompletionList: ResponseType, Hashable {

  /// Whether the list of completions is "complete" or not. When this value is `true`, the client should re-query the server when doing further filtering.
  public var isIncomplete: Bool

  /// The resulting completions.
  public var items: [CompletionItem]

  public init(isIncomplete: Bool, items: [CompletionItem]) {
    self.isIncomplete = isIncomplete
    self.items = items
  }
}

public struct HoverRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/hover"
  public typealias Response = HoverResponse?

  public var textDocument: TextDocumentIdentifier

  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

public struct HoverResponse: ResponseType, Hashable {

  public var contents: MarkupContent

  public var range: PositionRange?

  /// Extension!
  public var usr: String?

  /// Extension!
  public var definition: Location?

  public init(contents: MarkupContent, range: Range<Position>?, usr: String?, definition: Location?) {
    self.contents = contents
    self.range = range.map { PositionRange($0) }
    self.usr = usr
    self.definition = definition
  }
}

extension HoverResponse: Codable {
  private enum CodingKeys: String, CodingKey {
    case contents
    case range
    case usr = "sk_usr"
    case definition = "sk_definition"
  }
}

public struct DefinitionRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/definition"
  public typealias Response = [Location]

  public var textDocument: TextDocumentIdentifier

  public var position: Position
}

public struct ReferencesRequest: RequestType, Hashable {
  public static let method: String = "textDocument/references"
  public typealias Response = [Location]

  public var textDocument: TextDocumentIdentifier

  public var position: Position

  public var includeDeclaration: Bool?
}

public struct DocumentHighlightRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/documentHighlight"
  public typealias Response = [DocumentHighlight]?

  public var textDocument: TextDocumentIdentifier

  public var position: Position
}

public struct DocumentFormatting: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/formatting"
  public typealias Response = [TextEdit]?

  public var textDocument: TextDocumentIdentifier

  public var options: FormattingOptions
}

public struct DocumentRangeFormatting: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/rangeFormatting"
  public typealias Response = [TextEdit]?

  public var textDocument: TextDocumentIdentifier

  public var range: PositionRange

  public var options: FormattingOptions
}

public struct DocumentOnTypeFormatting: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/onTypeFormatting"
  public typealias Response = [TextEdit]?

  public var textDocument: TextDocumentIdentifier

  /// The position at which the request was sent, which is immediately after the trigger character.
  public var position: Position

  /// The character that triggered the formatting.
  public var ch: String

  public var options: FormattingOptions
}

public struct FormattingOptions: Codable, Hashable {

  /// The number of space characters in a tab.
  public var tabSize: Int

  /// Whether to use spaces instead of tabs.
  public var insertSpaces: Bool
}

/// Request for semantic information about the symbol at a given location **(LSP Extension)**.
///
/// This request looks up the symbol (if any) at a given text document location and returns
/// SymbolDetails for that location, including information such as the symbol's USR. The symbolInfo
/// request is not primarily designed for editors, but instead as an implementation detail of how
/// one LSP implementation (e.g. SourceKit) gets information from another (e.g. clangd) to use in
/// performing index queries or otherwise implementing the higher level requests such as definition.
///
/// - Parameters:
///   - textDocument: The document in which to interpret `position`.
///   - position: The document location at which to lookup symbol information.
///
/// - Returns: `[SymbolDetails]` for the given location, which may have multiple elements if there are
///   multiple references, or no elements if there is no symbol at the given location.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP and clangd. It does *not* require
/// any additional client or server capabilities to use.
public struct SymbolInfoRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/symbolInfo"
  public typealias Response = [SymbolDetails]

  /// The document in which to interpret `position`.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

/// Detailed information about a symbol, such as the response to a `SymbolInfoRequest`
/// **(LSP Extension)**.
public struct SymbolDetails: ResponseType, Hashable {

  /// The name of the symbol, if any.
  public var name: String?

  /// The name of the containing type for the symbol, if any.
  ///
  /// For example, in the following snippet, the `containerName` of `foo()` is `C`.
  ///
  /// ```c++
  /// class C {
  ///   void foo() {}
  /// }
  /// ```
  public var containerName: String?

  /// The USR of the symbol, if any.
  public var usr: String?

  /// An opaque identifier in a format known only to clangd.
  // public var id: String?

  /// Best known declaration or definition location without global knowledge.
  ///
  /// For a local or private variable, this is generally the canonical definition location -
  /// appropriate as a response to a `textDocument/definition` request. For global symbols this is
  /// the best known location within a single compilation unit. For example, in C++ this might be
  /// the declaration location from a header as opposed to the definition in some other
  /// translation unit.
  public var bestLocalDeclaration: Location? = nil

  public init(
    name: String?,
    containerName: String? = nil,
    usr: String?,
    bestLocalDeclaration: Location? = nil)
  {
    self.name = name
    self.containerName = containerName
    self.usr = usr
    self.bestLocalDeclaration = bestLocalDeclaration
  }
}
