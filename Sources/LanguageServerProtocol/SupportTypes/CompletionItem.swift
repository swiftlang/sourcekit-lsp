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

/// A single completion result.
public struct CompletionItem: Codable, Hashable {

  /// The display name of the completion.
  public var label: String

  /// The kind of completion item - e.g. method, property.
  public var kind: CompletionItemKind

  /// An extended human-readable name (longer than `label`, but simpler than `documentation`).
  public var detail: String?

  /// A human-readable string that represents a doc-comment.
  public var documentation: CompletionItemDocumentation?

  /// The name to use for sorting the result. If `nil`, use `label.
  public var sortText: String?

  /// The name to use for filtering the result. If `nil`, use `label.
  public var filterText: String?

  /// The (primary) edit to apply to the document if this completion is accepted.
  ///
  /// This takes precedence over `insertText`.
  ///
  /// - Note: The range of the edit must contain the completion position.
  public var textEdit: TextEdit?

  /// **Deprecated**: use `textEdit`
  ///
  /// The string to insert into the document. If `nil`, use `label.
  public var insertText: String?

  /// The format of the `textEdit.nextText` or `insertText` value.
  public var insertTextFormat: InsertTextFormat?

  /// Whether the completion is for a deprecated symbol.
  public var deprecated: Bool?

  public init(
    label: String,
    kind: CompletionItemKind,
    detail: String? = nil,
    documentation: CompletionItemDocumentation? = nil,
    sortText: String? = nil,
    filterText: String? = nil,
    textEdit: TextEdit? = nil,
    insertText: String? = nil,
    insertTextFormat: InsertTextFormat? = nil,
    deprecated: Bool? = nil)
  {
    self.label = label
    self.detail = detail
    self.sortText = sortText
    self.filterText = filterText
    self.textEdit = textEdit
    self.insertText = insertText
    self.insertTextFormat = insertTextFormat
    self.kind = kind
    self.deprecated = deprecated
  }
}

/// The format of the returned insertion text - either literal plain text or a snippet.
public enum InsertTextFormat: Int, Codable, Hashable {

  /// The text to insert is plain text.
  case plain = 1

  /// The text to insert is a "snippet", which may contain placeholders.
  case snippet = 2
}

public enum CompletionItemDocumentation: Hashable {
  case string(String)
  case markupContent(MarkupContent)
}

extension CompletionItemDocumentation: Codable {
  public init(from decoder: Decoder) throws {
    if let string = try? String(from: decoder) {
      self = .string(string)
    } else if let markupContent = try? MarkupContent(from: decoder) {
      self = .markupContent(markupContent)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or MarkupContent")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .string(let string):
      try string.encode(to: encoder)
    case .markupContent(let markupContent):
      try markupContent.encode(to: encoder)
    }
  }
}
