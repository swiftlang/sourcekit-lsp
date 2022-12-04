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
public struct TextDocumentEdit: Hashable, Codable {
  public enum Edit: Codable, Hashable {
    case textEdit(TextEdit)
    case annotatedTextEdit(AnnotatedTextEdit)

    public init(from decoder: Decoder) throws {
      if let annotated = try? AnnotatedTextEdit(from: decoder) {
        self = .annotatedTextEdit(annotated)
      } else if let edit = try? TextEdit(from: decoder) {
        self = .textEdit(edit)
      } else {
        let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected AnnotatedTextEdit or TextEdit")
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
}
