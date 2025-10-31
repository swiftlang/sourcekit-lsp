//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Re-open the given document, discarding any in-memory state.
///
/// This notification is designed to be used internally in SourceKit-LSP: When build setting have changed, we re-open
/// the document in sourcekitd to re-build its AST. This needs to be handled via a notification to ensure that no other
/// request for this document is executing at the same time.
///
/// **(LSP Extension)**
public struct ReopenTextDocumentNotification: LSPNotification, Hashable {
  public static let method: String = "textDocument/reopen"

  /// The document identifier and initial contents.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}
