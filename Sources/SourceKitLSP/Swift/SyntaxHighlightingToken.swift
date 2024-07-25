//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKLogging
import SourceKitD

/// A ranged token in the document used for syntax highlighting.
package struct SyntaxHighlightingToken: Hashable, Sendable {
  /// The range of the token in the document. Must be on a single line.
  package var range: Range<Position> {
    didSet {
      assert(range.lowerBound.line == range.upperBound.line)
    }
  }
  /// The token type.
  package var kind: SemanticTokenTypes
  /// Additional metadata about the token.
  package var modifiers: SemanticTokenModifiers

  /// The (inclusive) start position of the token.
  package var start: Position { range.lowerBound }
  /// The (exclusive) end position of the token.
  package var end: Position { range.upperBound }
  /// The length of the token in UTF-16 code units.
  package var utf16length: Int { end.utf16index - start.utf16index }

  package init(range: Range<Position>, kind: SemanticTokenTypes, modifiers: SemanticTokenModifiers = []) {
    assert(range.lowerBound.line == range.upperBound.line)

    self.range = range
    self.kind = kind
    self.modifiers = modifiers
  }

  package init(start: Position, utf16length: Int, kind: SemanticTokenTypes, modifiers: SemanticTokenModifiers = []) {
    let range = start..<Position(line: start.line, utf16index: start.utf16index + utf16length)
    self.init(range: range, kind: kind, modifiers: modifiers)
  }
}
