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

import Dispatch
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
package import SKUtilities
import SemanticIndex
package import SwiftSyntax

/// An immutable snapshot of a document at a given time.
///
/// ``DocumentSnapshot`` is always derived from a ``Document``. That is, the
/// data structure that is stored internally by the ``DocumentManager`` is a
/// ``Document``. The purpose of a ``DocumentSnapshot`` is to be able to work
/// with one version of a document without having to think about it changing.
package struct DocumentSnapshot: Identifiable, Sendable {
  /// An ID that uniquely identifies the version of the document stored in this
  /// snapshot.
  package struct ID: Hashable, Comparable, Sendable {
    package let uri: DocumentURI
    package let version: Int

    /// Returns `true` if the snapshots reference the same document but rhs has a
    /// later version than `lhs`.
    ///
    /// Snapshot IDs of different documents are not comparable to each other and
    /// will always return `false`.
    package static func < (lhs: DocumentSnapshot.ID, rhs: DocumentSnapshot.ID) -> Bool {
      return lhs.uri == rhs.uri && lhs.version < rhs.version
    }
  }

  package let id: ID
  package let language: Language
  package let lineTable: LineTable

  package var uri: DocumentURI { id.uri }
  package var version: Int { id.version }
  package var text: String { lineTable.content }

  package init(
    uri: DocumentURI,
    language: Language,
    version: Int,
    lineTable: LineTable
  ) {
    self.id = ID(uri: uri, version: version)
    self.language = language
    self.lineTable = lineTable
  }
}

package final class Document {
  package let uri: DocumentURI
  package let language: Language
  var latestVersion: Int
  var latestLineTable: LineTable

  init(uri: DocumentURI, language: Language, version: Int, text: String) {
    self.uri = uri
    self.language = language
    self.latestVersion = version
    self.latestLineTable = LineTable(text)
  }

  /// **Not thread safe!** Use `DocumentManager.latestSnapshot` instead.
  fileprivate var latestSnapshot: DocumentSnapshot {
    DocumentSnapshot(
      uri: self.uri,
      language: self.language,
      version: latestVersion,
      lineTable: latestLineTable
    )
  }
}

package final class DocumentManager: InMemoryDocumentManager, Sendable {

  package enum Error: Swift.Error {
    case alreadyOpen(DocumentURI)
    case missingDocument(DocumentURI)
  }

  // TODO: Migrate this to be an AsyncQueue (https://github.com/swiftlang/sourcekit-lsp/issues/1597)
  private let queue: DispatchQueue = DispatchQueue(label: "document-manager-queue")

  // `nonisolated(unsafe)` is fine because `documents` is guarded by queue.
  private nonisolated(unsafe) var documents: [DocumentURI: Document] = [:]

  package init() {}

  /// All currently opened documents.
  package var openDocuments: Set<DocumentURI> {
    return queue.sync {
      return Set(documents.keys)
    }
  }

  /// Opens a new document with the given content and metadata.
  ///
  /// - returns: The initial contents of the file.
  /// - throws: Error.alreadyOpen if the document is already open.
  @discardableResult
  package func open(_ uri: DocumentURI, language: Language, version: Int, text: String) throws -> DocumentSnapshot {
    return try queue.sync {
      let document = Document(uri: uri, language: language, version: version, text: text)
      if nil != documents.updateValue(document, forKey: uri) {
        throw Error.alreadyOpen(uri)
      }
      return document.latestSnapshot
    }
  }

  /// Closes the given document.
  ///
  /// - returns: The initial contents of the file.
  /// - throws: Error.missingDocument if the document is not open.
  package func close(_ uri: DocumentURI) throws {
    try queue.sync {
      if nil == documents.removeValue(forKey: uri) {
        throw Error.missingDocument(uri)
      }
    }
  }

  /// Applies the given edits to the document.
  ///
  /// - Parameters:
  ///   - uri: The URI of the document to update
  ///   - newVersion: The new version of the document. Must be greater than the
  ///     latest version of the document.
  ///   - edits: The edits to apply to the document
  /// - Returns: The snapshot of the document before the edit, the snapshot
  ///   of the document after the edit, and the edits. The edits are sequential, ie.
  ///   the edits are expected to be applied in order and later values in this array
  ///   assume that previous edits are already applied.
  @discardableResult
  package func edit(
    _ uri: DocumentURI,
    newVersion: Int,
    edits: [TextDocumentContentChangeEvent]
  ) throws -> (preEditSnapshot: DocumentSnapshot, postEditSnapshot: DocumentSnapshot, edits: [SourceEdit]) {
    return try queue.sync {
      guard let document = documents[uri] else {
        throw Error.missingDocument(uri)
      }
      let preEditSnapshot = document.latestSnapshot

      var sourceEdits: [SourceEdit] = []
      for edit in edits {
        sourceEdits.append(SourceEdit(edit: edit, lineTableBeforeEdit: document.latestLineTable))

        if let range = edit.range {
          document.latestLineTable.replace(
            fromLine: range.lowerBound.line,
            utf16Offset: range.lowerBound.utf16index,
            toLine: range.upperBound.line,
            utf16Offset: range.upperBound.utf16index,
            with: edit.text
          )
        } else {
          // Full text replacement.
          document.latestLineTable = LineTable(edit.text)
        }
      }

      if newVersion <= document.latestVersion {
        logger.error("Document version did not increase on edit from \(document.latestVersion) to \(newVersion)")
      }
      document.latestVersion = newVersion
      return (preEditSnapshot, document.latestSnapshot, sourceEdits)
    }
  }

  package func latestSnapshot(_ uri: DocumentURI) throws -> DocumentSnapshot {
    return try queue.sync {
      guard let document = documents[uri] else {
        throw ResponseError.unknown("Failed to find snapshot for '\(uri)'")
      }
      return document.latestSnapshot
    }
  }

  /// Returns the latest open snapshot of `uri` or, if no document with that URI is open, reads the file contents of
  /// that file from disk.
  package func latestSnapshotOrDisk(_ uri: DocumentURI, language: Language) -> DocumentSnapshot? {
    if let snapshot = try? self.latestSnapshot(uri) {
      return snapshot
    }
    return try? DocumentSnapshot(withContentsFromDisk: uri, language: language)
  }

  package func fileHasInMemoryModifications(_ uri: DocumentURI) -> Bool {
    guard let document = try? latestSnapshot(uri), let fileURL = uri.fileURL else {
      return false
    }

    guard let onDiskFileContents = try? String(contentsOf: fileURL, encoding: .utf8) else {
      // If we can't read the file on disk, it can't match any on-disk state, so it's in-memory state
      return true
    }
    return onDiskFileContents != document.lineTable.content
  }
}

fileprivate extension SourceEdit {
  /// Constructs a `SourceEdit` from the given `TextDocumentContentChangeEvent`.
  ///
  /// Returns `nil` if the `TextDocumentContentChangeEvent` refers to line:column positions that don't exist in
  /// `LineTable`.
  init(edit: TextDocumentContentChangeEvent, lineTableBeforeEdit: LineTable) {
    if let range = edit.range {
      let offset = lineTableBeforeEdit.utf8OffsetOf(
        line: range.lowerBound.line,
        utf16Column: range.lowerBound.utf16index
      )
      let end = lineTableBeforeEdit.utf8OffsetOf(
        line: range.upperBound.line,
        utf16Column: range.upperBound.utf16index
      )
      self.init(
        range: AbsolutePosition(utf8Offset: offset)..<AbsolutePosition(utf8Offset: end),
        replacement: edit.text
      )
    } else {
      self.init(
        range: AbsolutePosition(utf8Offset: 0)..<AbsolutePosition(utf8Offset: lineTableBeforeEdit.content.utf8.count),
        replacement: edit.text
      )
    }
  }
}
