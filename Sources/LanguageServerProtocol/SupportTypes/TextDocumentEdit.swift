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

  /// The potentially versioned document to which these edits apply.
  public var textDocument: VersionedTextDocumentIdentifier

  /// The edits to be applied, which must be non-overlapping.
  public var edits: [TextEdit]

  public init(textDocument: VersionedTextDocumentIdentifier, edits: [TextEdit]) {
    self.textDocument = textDocument
    self.edits = edits
  }
}
