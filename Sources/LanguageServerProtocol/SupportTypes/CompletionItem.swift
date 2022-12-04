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

/// Additional details for a completion item label.
public struct CompletionItemLabelDetails: Codable, Hashable {

  /// An optional string which is rendered less prominently directly after
  /// {@link CompletionItem.label label}, without any spacing. Should be
  /// used for function signatures or type annotations.
  public var detail: String?

  /// An optional string which is rendered less prominently after
  /// `CompletionItemLabelDetails.detail`. Should be used for fully qualified
  /// names or file path.
  public var description: String?

  public init(detail: String? = nil, description: String? = nil) {
    self.detail = detail
    self.description = description
  }
}

/// Completion item tags are extra annotations that tweak the rendering of a
/// completion item.
public struct CompletionItemTag: RawRepresentable, Codable, Hashable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Render a completion as obsolete, usually using a strike-out.
  public static let deprecated = CompletionItemTag(rawValue: 1)
}

public enum CompletionItemEdit: Codable, Hashable {
  case textEdit(TextEdit)
  case insertReplaceEdit(InsertReplaceEdit)

  public init(from decoder: Decoder) throws {
    if let textEdit = try? TextEdit(from: decoder) {
      self = .textEdit(textEdit)
    } else if let insertReplaceEdit = try? InsertReplaceEdit(from: decoder) {
      self = .insertReplaceEdit(insertReplaceEdit)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected TextEdit or InsertReplaceEdit")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .textEdit(let textEdit):
      try textEdit.encode(to: encoder)
    case .insertReplaceEdit(let insertReplaceEdit):
      try insertReplaceEdit.encode(to: encoder)
    }
  }
}

/// A single completion result.
public struct CompletionItem: ResponseType, Codable, Hashable {

  /// The display name of the completion.
  public var label: String

  /// Additional details for the label
  public var labelDetails: CompletionItemLabelDetails?

  /// The kind of completion item - e.g. method, property.
  public var kind: CompletionItemKind

  /// Tags for this completion item.
  public var tags: [CompletionItemTag]?

  /// An extended human-readable name (longer than `label`, but simpler than `documentation`).
  public var detail: String?

  /// A human-readable string that represents a doc-comment.
  public var documentation: StringOrMarkupContent?

  /// Whether the completion is for a deprecated symbol.
  public var deprecated: Bool?

  /// Select this item when showing.
  ///
  /// *Note* that only one completion item can be selected and that the
  /// tool / client decides which item that is. The rule is that the *first*
  /// item of those that match best is selected.
  public var preselect: Bool?

  /// The name to use for sorting the result. If `nil`, use `label.
  public var sortText: String?

  /// The name to use for filtering the result. If `nil`, use `label.
  public var filterText: String?

  /// **Deprecated**: use `textEdit`
  ///
  /// The string to insert into the document. If `nil`, use `label.
  public var insertText: String?

  /// The format of the `textEdit.nextText` or `insertText` value.
  public var insertTextFormat: InsertTextFormat?

  /// How whitespace and indentation is handled during completion
  /// item insertion. If not provided the client's default value depends on
  /// the `textDocument.completion.insertTextMode` client capability.
  public var insertTextMode: InsertTextMode?

  /// The (primary) edit to apply to the document if this completion is accepted.
  ///
  /// This takes precedence over `insertText`.
  ///
  /// - Note: The range of the edit must contain the completion position.
  public var textEdit: CompletionItemEdit?

  /// The edit text used if the completion item is part of a CompletionList and
  /// CompletionList defines an item default for the text edit range.
  ///
  /// Clients will only honor this property if they opt into completion list
  /// item defaults using the capability `completionList.itemDefaults`.
  ///
  /// If not provided and a list's default range is provided the label
  /// property is used as a text.
  public var textEditText: String?

  /// An optional array of additional text edits that are applied when
  /// selecting this completion. Edits must not overlap (including the same
  /// insert position) with the main edit nor with themselves.
  ///
  /// Additional text edits should be used to change text unrelated to the
  /// current cursor position (for example adding an import statement at the
  /// top of the file if the completion item will insert an unqualified type).
  public var additionalTextEdits: [TextEdit]?

  /// An optional set of characters that when pressed while this completion is
  /// active will accept it first and then type that character. *Note* that all
  /// commit characters should have `length=1` and that superfluous characters
  /// will be ignored.
  public var commitCharacters: [String]?

  /// An optional command that is executed *after* inserting this completion.
  /// *Note* that additional modifications to the current document should be
  /// described with the additionalTextEdits-property.
  public var command: Command?

  /// A data entry field that is preserved on a completion item between
  /// a completion and a completion resolve request.
  public var data: LSPAny?

  public init(
    label: String,
    labelDetails: CompletionItemLabelDetails? = nil,
    kind: CompletionItemKind,
    tags: [CompletionItemTag]? = nil,
    detail: String? = nil,
    documentation: StringOrMarkupContent? = nil,
    deprecated: Bool? = nil,
    preselect: Bool? = nil,
    sortText: String? = nil,
    filterText: String? = nil,
    insertText: String? = nil,
    insertTextFormat: InsertTextFormat? = nil,
    insertTextMode: InsertTextMode? = nil,
    textEdit: CompletionItemEdit? = nil,
    textEditText: String? = nil,
    additionalTextEdits: [TextEdit]? = nil,
    commitCharacters: [String]? = nil,
    command: Command? = nil,
    data: LSPAny? = nil
  ) {
    self.label = label
    self.labelDetails = labelDetails
    self.kind = kind
    self.tags = tags
    self.detail = detail
    self.documentation = documentation
    self.deprecated = deprecated
    self.preselect = preselect
    self.sortText = sortText
    self.filterText = filterText
    self.insertText = insertText
    self.insertTextFormat = insertTextFormat
    self.insertTextMode = insertTextMode
    self.textEdit = textEdit
    self.textEditText = textEditText
    self.additionalTextEdits = additionalTextEdits
    self.commitCharacters = commitCharacters
    self.command = command
    self.data = data
  }
}

/// The format of the returned insertion text - either literal plain text or a snippet.
public enum InsertTextFormat: Int, Codable, Hashable {

  /// The text to insert is plain text.
  case plain = 1

  /// The text to insert is a "snippet", which may contain placeholders.
  case snippet = 2
}

/// How whitespace and indentation is handled during completion
/// item insertion.
public struct InsertTextMode: RawRepresentable, Codable, Hashable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

   /// The insertion or replace strings is taken as it is. If the
   /// value is multi line the lines below the cursor will be
   /// inserted using the indentation defined in the string value.
   /// The client will not apply any kind of adjustments to the
   /// string.
  public static let asIs = InsertTextMode(rawValue: 1)

   /// The editor adjusts leading whitespace of new lines so that
   /// they match the indentation up to the cursor of the line for
   /// which the item is accepted.
   ///
   /// Consider a line like this: <2tabs><cursor><3tabs>foo. Accepting a
   /// multi line completion item is indented using 2 tabs and all
   /// following lines inserted will be indented using 2 tabs as well.
  public static let adjustIndentation = InsertTextMode(rawValue: 2)
}
