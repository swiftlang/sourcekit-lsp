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

/// Edit within a particular document.
///
/// For an edit where the document is implied, use `TextEdit`.
public struct TextDocumentEdit: Hashable, Codable, Sendable {
  public enum Edit: Codable, Hashable, Sendable {
    case textEdit(TextEdit)
    case annotatedTextEdit(AnnotatedTextEdit)

    public init(from decoder: Decoder) throws {
      if let annotated = try? AnnotatedTextEdit(from: decoder) {
        self = .annotatedTextEdit(annotated)
      } else if let edit = try? TextEdit(from: decoder) {
        self = .textEdit(edit)
      } else {
        let context = DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected AnnotatedTextEdit or TextEdit"
        )
        throw DecodingError.dataCorrupted(context)
      }
    }

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .textEdit(let edit):
        try edit.encode(to: encoder)
      case .annotatedTextEdit(let annotated):
        try annotated.encode(to: encoder)
      }
    }
  }

  /// The potentially versioned document to which these edits apply.
  public var textDocument: OptionalVersionedTextDocumentIdentifier

  /// The edits to be applied, which must be non-overlapping.
  public var edits: [Edit]

  public init(textDocument: OptionalVersionedTextDocumentIdentifier, edits: [Edit]) {
    self.textDocument = textDocument
    self.edits = edits
  }

  public enum CodingKeys: String, CodingKey {
    case kind
    case textDocument
    case edits
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("textDocumentEdit", forKey: .kind)
    try container.encode(self.textDocument, forKey: .textDocument)
    try container.encode(self.edits, forKey: .edits)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    guard kind == "textDocumentEdit" else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Kind of TextDocumentEdit is not 'textDocumentEdit'"
      )
    }
    self.textDocument = try container.decode(OptionalVersionedTextDocumentIdentifier.self, forKey: .textDocument)
    self.edits = try container.decode([Edit].self, forKey: .edits)
  }
}
