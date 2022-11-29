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

/// Notification from the client that a new document is open and its content should be managed by
/// the text synchronization notifications until it has been closed.
///
/// The `didOpen` notification provides the initial contents of the document. Thereafter, any
/// queries that need the content of this document should use the contents provided here (or updated
/// via subsequent `didChange` notifications) and should ignore the contents on disk.
///
/// An open document can be modified using the `didChange` notification, and when done closed using
/// the `didClose` notification. Once closed, the server can use the contents on disk, if needed.
/// A document can only be opened once at a time, and must be balanced by a `didClose` before being
/// opened again.
///
/// Servers that provide document synchronization should set the `textDocumentSync` server
/// capability.
///
/// - Parameter textDocument: The document identifier and initial contents.
public struct DidOpenTextDocumentNotification: NotificationType, Hashable {
  public static let method: String = "textDocument/didOpen"

  /// The document identifier and initial contents.
  public var textDocument: TextDocumentItem

  public init(textDocument: TextDocumentItem) {
    self.textDocument = textDocument
  }
}

/// Notification that the given document is closed and no longer managed by the text synchronization
/// notifications.
///
/// The document must have previously been opened with `didOpen`. Closing the document returns
/// management of the document contents to disk, if appropriate.
///
/// - Parameter textDocument: The document to close, which must be currently open.
public struct DidCloseTextDocumentNotification: NotificationType, Hashable {
  public static let method: String = "textDocument/didClose"

  /// The document to close, which must be currently open.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

/// Notification that the contents of the given document have been changed.
///
/// Updates the content of a document previously opened with `didOpen` by applying a list of
/// changes, which may either be full document replacements, or incremental edits.
///
/// Servers that support incremental edits should set the `change` text document sync option.
///
/// - Parameters:
///   - textDocument: The document to change and its current version identifier.
///   - contentChanges: Edits to the document.
public struct DidChangeTextDocumentNotification: NotificationType, Hashable {
  public static let method: String = "textDocument/didChange"

  /// The document that did change. The version number points
  /// to the version after all provided content changes have
  /// been applied.
  public var textDocument: VersionedTextDocumentIdentifier

  /// The actual content changes. The content changes describe single state
  /// changes to the document. So if there are two content changes c1 (at
  /// array index 0) and c2 (at array index 1) for a document in state S then
  /// c1 moves the document from S to S' and c2 from S' to S''. So c1 is
  /// computed on the state S and c2 is computed on the state S'.
  ///
  /// To mirror the content of a document using change events use the following
  /// approach:
  /// - start with the same initial content
  /// - apply the 'textDocument/didChange' notifications in the order you
  ///   receive them.
  /// - apply the `TextDocumentContentChangeEvent`s in a single notification
  ///   in the order you receive them.
  public var contentChanges: [TextDocumentContentChangeEvent]

  /// Force the LSP to rebuild its AST for the given file. This is useful for clangd to workaround clangd's assumption that
  /// missing header files will stay missing.
  /// **LSP Extension from clangd**.
  public var forceRebuild: Bool? = nil

  public init(
    textDocument: VersionedTextDocumentIdentifier,
    contentChanges: [TextDocumentContentChangeEvent],
    forceRebuild: Bool? = nil)
  {
    self.textDocument = textDocument
    self.contentChanges = contentChanges
    self.forceRebuild = forceRebuild
  }
}

/// Notification that the given document will be saved.
///
/// - Parameters:
///   - textDocument: The document that will be saved.
///   - reason: Whether this was user-initiated, auto-saved, etc.
///
/// Servers that support willSave should set the `willSave` text document sync option.
public struct WillSaveTextDocumentNotification: TextDocumentNotification, Hashable {
  public static let method: String = "textDocument/willSave"

  /// The document that will be saved.
  public var textDocument: TextDocumentIdentifier

  /// Whether this is user-initiated save, auto-saved, etc.
  public var reason: TextDocumentSaveReason
}

/// Notification that the given document was saved.
///
/// - Parameters:
///   - textDocument: The document that was saved.
///   - text: The content of the document at the time of save.
///
/// Servers that support didSave should set the `save` text document sync option.
public struct DidSaveTextDocumentNotification: TextDocumentNotification, Hashable {
  public static let method: String = "textDocument/didSave"

  /// The document that was saved.
  public var textDocument: TextDocumentIdentifier

  /// The content of the document at the time of save.
  ///
  /// Only provided if the server specified `includeText == true`.
  public var text: String?
}

/// The open notification is sent from the client to the server when a notebook document is opened. It is only sent by a client if the server requested the synchronization mode `notebook` in its `notebookDocumentSync` capability.
public struct DidOpenNotebookDocumentNotification: NotificationType, Hashable {
  public static let method: String = "notebookDocument/didOpen"

  /// The notebook document that got opened.
  public var notebookDocument: NotebookDocument

  /// The text documents that represent the content
  /// of a notebook cell.
  public var cellTextDocuments: [TextDocumentItem]

  public init(notebookDocument: NotebookDocument, cellTextDocuments: [TextDocumentItem]) {
    self.notebookDocument = notebookDocument
    self.cellTextDocuments = cellTextDocuments
  }
}

/// The change notification is sent from the client to the server when a notebook document changes. It is only sent by a client if the server requested the synchronization mode `notebook` in its `notebookDocumentSync` capability.
public struct DidChangeNotebookDocumentNotification: NotificationType, Hashable {
  public static var method: String = "notebookDocument/didChange"
  
  /// The notebook document that did change. The version number points
  /// to the version after all provided changes have been applied.
  public var notebookDocument: VersionedNotebookDocumentIdentifier

  /// The actual changes to the notebook document.
  ///
  /// The change describes single state change to the notebook document.
  /// So it moves a notebook document, its cells and its cell text document
  /// contents from state S to S'.
  ///
  /// To mirror the content of a notebook using change events use the
  /// following approach:
  /// - start with the same initial content
  /// - apply the 'notebookDocument/didChange' notifications in the order
  ///   you receive them.
  public var change: NotebookDocumentChangeEvent

  public init(notebookDocument: VersionedNotebookDocumentIdentifier, change: NotebookDocumentChangeEvent) {
    self.notebookDocument = notebookDocument
    self.change = change
  }
}

/// The save notification is sent from the client to the server when a notebook document is saved. It is only sent by a client if the server requested the synchronization mode `notebook` in its `notebookDocumentSync` capability.
public struct DidSaveNotebookDocumentNotification: NotificationType {
  public static var method: String = "notebookDocument/didSave"

  /// The notebook document that got saved.
  public var notebookDocument: NotebookDocumentIdentifier

  public init(notebookDocument: NotebookDocumentIdentifier) {
    self.notebookDocument = notebookDocument
  }
}

/// The close notification is sent from the client to the server when a notebook document is closed. It is only sent by a client if the server requested the synchronization mode `notebook` in its `notebookDocumentSync` capability.
public struct DidCloseNotebookDocumentNotification: NotificationType {
  public static var method: String = "notebookDocument/didClose"

  /// The notebook document that got closed.
  public var notebookDocument: NotebookDocumentIdentifier

  /// The text documents that represent the content
  /// of a notebook cell that got closed.
  public var cellTextDocuments: [TextDocumentIdentifier]

  public init(notebookDocument: NotebookDocumentIdentifier, cellTextDocuments: [TextDocumentIdentifier]) {
    self.notebookDocument = notebookDocument
    self.cellTextDocuments = cellTextDocuments
  }
}
