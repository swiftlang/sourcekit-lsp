//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// **LSP Extension** Notification from the server about a per-file status update for
/// the client.
///
/// Requires a private SourceKit extension.
public struct SourceKitFileStatusNotification: TextDocumentNotification, Hashable {
  public static let method: String = "textDocument/sourcekit.filestatus"

  /// The `textDocument` this status notification is for.
  public var textDocument: TextDocumentIdentifier

  /// File state used to stylize the status (e.g. with an icon).
  public var state: SourceKitFileState

  /// Severity of the status. Used to stylize the status (e.g. with a color or icon).
  public var severity: DiagnosticSeverity

  /// Human readable description.
  public var message: String

  /// Short operation label for the status, if any.
  public var operation: String?

  public init(
    textDocument: TextDocumentIdentifier,
    state: SourceKitFileState,
    severity: DiagnosticSeverity,
    message: String,
    operation: String? = nil
  ) {
    self.textDocument = textDocument
    self.state = state
    self.severity = severity
    self.message = message
    self.operation = operation
  }
}
