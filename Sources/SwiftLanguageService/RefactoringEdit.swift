//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) package import LanguageServerProtocol
import SourceKitD

/// Represents an edit from semantic refactor response. Notionally, a subclass of `TextEdit`
package struct RefactoringEdit: Hashable, Sendable, Codable {
  /// The range of text to be replaced.
  @CustomCodable<PositionRange>
  package var range: Range<Position>

  /// The new text.
  package var newText: String

  /// If the new text of the edit should not be applied to the original source
  /// file but to a separate buffer, a fake name for that buffer. For example
  /// for expansion of macros, this is @ followed by the mangled name of the
  /// macro expansion, followed by .swift.
  package var bufferName: String?

  package init(range: Range<Position>, newText: String, bufferName: String?) {
    self.range = range
    self.newText = newText
    self.bufferName = bufferName
  }
}

extension RefactoringEdit: LSPAnyCodable {}
