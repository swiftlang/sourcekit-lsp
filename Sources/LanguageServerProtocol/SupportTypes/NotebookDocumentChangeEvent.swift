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

/// A change describing how to move a `NotebookCell`
/// array from state S to S'.
public struct NotebookCellArrayChange: Codable, Hashable {
  /// The start offset of the cell that changed.
  public var start: Int

  /// The deleted cells
  public var deleteCount: Int

  /// The new cells, if any
  public var cells: [NotebookCell]?

  public init(start: Int, deleteCount: Int, cells: [NotebookCell]? = nil) {
    self.start = start
    self.deleteCount = deleteCount
    self.cells = cells
  }
}

/// A change event for a notebook document.
public struct NotebookDocumentChangeEvent: Codable, Hashable {
  public struct CellsStructure: Codable, Hashable {
    /// The change to the cell array.
    public var array: NotebookCellArrayChange

    /// Additional opened cell text documents.
    public var didOpen: [TextDocumentItem]?

    /// Additional closed cell text documents.
    public var didClose: [TextDocumentIdentifier]?

    public init(array: NotebookCellArrayChange, didOpen: [TextDocumentItem]? = nil, didClose: [TextDocumentIdentifier]? = nil) {
      self.array = array
      self.didOpen = didOpen
      self.didClose = didClose
    }
  }

  public struct CellsTextContent: Codable, Hashable {
    public var document: VersionedTextDocumentIdentifier
    public var changes: [TextDocumentContentChangeEvent]

    public init(document: VersionedTextDocumentIdentifier, changes: [TextDocumentContentChangeEvent]) {
      self.document = document
      self.changes = changes
    }
  }

  public struct Cells: Codable, Hashable {
    /// Changes to the cell structure to add or
    /// remove cells.
    public var structure: CellsStructure?

    /// Changes to notebook cells properties like its
    /// kind, execution summary or metadata.
    public var data: [NotebookCell]?

    /// Changes to the text content of notebook cells.
    public var textContent: [CellsTextContent]?

    public init(structure: CellsStructure? = nil, data: [NotebookCell]? = nil, textContent: [CellsTextContent]? = nil) {
      self.structure = structure
      self.data = data
      self.textContent = textContent
    }
  }

  /// The changed meta data if any.
  public var metadata: LSPObject?

  /// Changes to cells
  public var cells: Cells?

  public init(metadata: LSPObject? = nil, cells: Cells? = nil) {
    self.metadata = metadata
    self.cells = cells
  }
}
