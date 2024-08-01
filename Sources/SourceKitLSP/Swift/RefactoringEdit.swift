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

import LanguageServerProtocol
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
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.newText = newText
    self.bufferName = bufferName
  }
}

extension RefactoringEdit: LSPAnyCodable {
  package init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard case .dictionary(let rangeDict) = dictionary[CodingKeys.range.stringValue],
      case .string(let newText) = dictionary[CodingKeys.newText.stringValue]
    else {
      return nil
    }

    guard let range = Range<Position>(fromLSPDictionary: rangeDict) else {
      return nil
    }

    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.newText = newText

    if case .string(let bufferName) = dictionary[CodingKeys.bufferName.stringValue] {
      self.bufferName = bufferName
    } else {
      self.bufferName = nil
    }
  }

  package func encodeToLSPAny() -> LSPAny {
    guard let bufferName = bufferName else {
      return .dictionary([
        CodingKeys.range.stringValue: range.encodeToLSPAny(),
        CodingKeys.newText.stringValue: .string(newText),
      ])
    }

    return .dictionary([
      CodingKeys.range.stringValue: range.encodeToLSPAny(),
      CodingKeys.newText.stringValue: .string(newText),
      CodingKeys.bufferName.stringValue: .string(bufferName),
    ])
  }
}
