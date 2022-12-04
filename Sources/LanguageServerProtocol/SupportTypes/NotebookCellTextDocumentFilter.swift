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

/// A notebook document filter denotes a notebook document by different properties.
public struct NotebookDocumentFilter: Codable, Hashable {
  /// The type of the enclosing notebook.
  public var notebookType: String?

  /// A Uri [scheme](#Uri.scheme), like `file` or `untitled`.
  public var scheme: String?

  /// A glob pattern.
  public var pattern: String?

  public init(notebookType: String? = nil, scheme: String? = nil, pattern: String? = nil) {
    self.notebookType = notebookType
    self.scheme = scheme
    self.pattern = pattern
  }
}

/// A notebook cell text document filter denotes a cell text
/// document by different properties.
public struct NotebookCellTextDocumentFilter: Codable, Hashable {
  public enum NotebookFilter: Codable, Hashable {
    case string(String)
    case notebookDocumentFilter(NotebookDocumentFilter)

    public init(from decoder: Decoder) throws {
      if let string = try? String(from: decoder) {
        self = .string(string)
      } else if let filter = try? NotebookDocumentFilter(from: decoder) {
        self = .notebookDocumentFilter(filter)
      } else {
        let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "NotebookFilter must be either a String or NotebookDocumentFilter")
        throw DecodingError.dataCorrupted(context)
      }
    }

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .string(let string):
        try string.encode(to: encoder)
      case .notebookDocumentFilter(let filter):
        try filter.encode(to: encoder)
      }
    }
  }

  /// A filter that matches against the notebook
  /// containing the notebook cell. If a string
  /// value is provided it matches against the
  /// notebook type. '*' matches every notebook.
  public var notebook: NotebookFilter

  /// A language id like `python`.
  ///
  /// Will be matched against the language id of the
  /// notebook cell document. '*' matches every language.
  public var language: String?

  public init(notebook: NotebookFilter, language: String? = nil) {
    self.notebook = notebook
    self.language = language
  }
}
