//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct NotebookDocument: Codable, Hashable {

  /// The notebook document's URI.
  public var uri: DocumentURI

  /// The type of the notebook.
  public var notebookType: String

  /// The version number of this document (it will increase after each
  /// change, including undo/redo).
  public var version: Int

  /// Additional metadata stored with the notebook
  /// document.
  public var metadata: LSPObject?

  /// The cells of a notebook.
  public var cells: [NotebookCell]

  public init(uri: DocumentURI, notebookType: String, version: Int, metadata: LSPObject? = nil, cells: [NotebookCell]) {
    self.uri = uri
    self.notebookType = notebookType
    self.version = version
    self.metadata = metadata
    self.cells = cells
  }
}

/// A notebook cell kind.
public struct NotebookCellKind: RawRepresentable, Codable, Hashable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// A markup-cell is formatted source that is used for display.
  public static var markup = NotebookCellKind(rawValue: 1)

  /// A code-cell is source code.
  public static var code = NotebookCellKind(rawValue: 2)
}

public struct ExecutionSummary: Codable, Hashable {
  /// A strict monotonically increasing value
  /// indicating the execution order of a cell
  /// inside a notebook.
  public var executionOrder: Int

  /// Whether the execution was successful or
  /// not if known by the client.
  public var success: Bool?

  public init(executionOrder: Int, success: Bool?) {
    self.executionOrder = executionOrder
    self.success = success
  }
}

/// A notebook cell.
///
/// A cell's document URI must be unique across ALL notebook
/// cells and can therefore be used to uniquely identify a
/// notebook cell or the cell's text document.
public struct NotebookCell: Codable, Hashable {

  /// The cell's kind
  public var kind: NotebookCellKind

  /// The URI of the cell's text document content.
  public var document: DocumentURI

  /// Additional metadata stored with the cell.
  public var metadata: LSPObject?

  /// Additional execution summary information if supported by the client.
  public var executionSummary: ExecutionSummary?

  public init(kind: NotebookCellKind, document: DocumentURI, metadata: LSPObject? = nil, executionSummary: ExecutionSummary? = nil) {
    self.kind = kind
    self.document = document
    self.metadata = metadata
    self.executionSummary = executionSummary
  }
}
