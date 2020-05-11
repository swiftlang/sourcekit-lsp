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
import LanguageServerProtocol
import LSPLogging
import SKSupport

public struct DocumentSnapshot {
  public var document: Document
  public var version: Int
  public var lineTable: LineTable
  public var text: String { return lineTable.content }

  public init(document: Document, version: Int, lineTable: LineTable) {
    self.document = document
    self.version = version
    self.lineTable = lineTable
  }

  func index(of pos: Position) -> String.Index? {
    return lineTable.stringIndexOf(line: pos.line, utf16Column: pos.utf16index)
  }
}

public final class Document {
  public let uri: DocumentURI
  public let language: Language
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
    return DocumentSnapshot(document: self, version: latestVersion, lineTable: latestLineTable)
  }
}

public final class DocumentManager {

  public enum Error: Swift.Error {
    case alreadyOpen(DocumentURI)
    case missingDocument(DocumentURI)
  }

  let queue: DispatchQueue = DispatchQueue(label: "document-manager-queue")

  var documents: [DocumentURI: Document] = [:]

  /// All currently opened documents.
  public var openDocuments: Set<DocumentURI> {
    return queue.sync {
      return Set(documents.keys)
    }
  }

  /// Opens a new document with the given content and metadata.
  ///
  /// - returns: The initial contents of the file.
  /// - throws: Error.alreadyOpen if the document is already open.
  @discardableResult
  public func open(_ uri: DocumentURI, language: Language, version: Int, text: String) throws -> DocumentSnapshot {
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
  public func close(_ uri: DocumentURI) throws {
    try queue.sync {
      if nil == documents.removeValue(forKey: uri) {
        throw Error.missingDocument(uri)
      }
    }
  }

  /// Applies the given edits to the document.
  ///
  /// - parameter editCallback: Optional closure to call for each edit.
  /// - parameter before: The document contents *before* the edit is applied.
  /// - returns: The contents of the file after all the edits are applied.
  /// - throws: Error.missingDocument if the document is not open.
  @discardableResult
  public func edit(_ uri: DocumentURI, newVersion: Int, edits: [TextDocumentContentChangeEvent], editCallback: ((_ before: DocumentSnapshot, TextDocumentContentChangeEvent) -> Void)? = nil) throws -> DocumentSnapshot {
    return try queue.sync {
      guard let document = documents[uri] else {
        throw Error.missingDocument(uri)
      }

      for edit in edits {
        if let f = editCallback {
          f(document.latestSnapshot, edit)
        }

        if let range = edit.range  {

          document.latestLineTable.replace(
            fromLine: range.lowerBound.line,
            utf16Offset: range.lowerBound.utf16index,
            toLine: range.upperBound.line,
            utf16Offset: range.upperBound.utf16index,
            with: edit.text)

        } else {
          // Full text replacement.
          document.latestLineTable = LineTable(edit.text)
        }

      }

      document.latestVersion = newVersion
      return document.latestSnapshot
    }
  }

  public func latestSnapshot(_ uri: DocumentURI) -> DocumentSnapshot? {
    return queue.sync {
      guard let document = documents[uri] else {
        return nil
      }
      return document.latestSnapshot
    }
  }
}

extension DocumentManager {

  // MARK: - LSP notification handling

  /// Convenience wrapper for `open(_:language:version:text:)` that logs on failure.
  @discardableResult
  func open(_ note: DidOpenTextDocumentNotification) -> DocumentSnapshot? {
    let doc = note.textDocument
    return orLog("failed to open document", level: .error) {
      try open(doc.uri, language: doc.language, version: doc.version, text: doc.text)
    }
  }

  /// Convenience wrapper for `close(_:)` that logs on failure.
  func close(_ note: DidCloseTextDocumentNotification) {
    orLog("failed to close document", level: .error) {
      try close(note.textDocument.uri)
    }
  }

  /// Convenience wrapper for `edit(_:newVersion:edits:editCallback:)` that logs on failure.
  @discardableResult
  func edit(_ note: DidChangeTextDocumentNotification, editCallback: ((_ before: DocumentSnapshot, TextDocumentContentChangeEvent) -> Void)? = nil) -> DocumentSnapshot? {
    return orLog("failed to edit document", level: .error) {
      try edit(note.textDocument.uri, newVersion: note.textDocument.version ?? -1, edits: note.contentChanges, editCallback: editCallback)
    }
  }
}
