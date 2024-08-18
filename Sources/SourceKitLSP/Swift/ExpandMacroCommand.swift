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

package struct ExpandMacroCommand: SwiftCommand {
  package static let identifier: String = "expand.macro.command"

  /// The name of this refactoring action.
  package var title = "Expand Macro"

  /// The sourcekitd identifier of the refactoring action.
  package var actionString = "source.refactoring.kind.expand.macro"

  /// The range to expand.
  package var positionRange: Range<Position>

  /// The text document related to the refactoring action.
  package var textDocument: TextDocumentIdentifier

  package init(positionRange: Range<Position>, textDocument: TextDocumentIdentifier) {
    self.positionRange = positionRange
    self.textDocument = textDocument
  }

  package init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard case .dictionary(let documentDict)? = dictionary[CodingKeys.textDocument.stringValue],
      case .string(let title)? = dictionary[CodingKeys.title.stringValue],
      case .string(let actionString)? = dictionary[CodingKeys.actionString.stringValue],
      case .dictionary(let rangeDict)? = dictionary[CodingKeys.positionRange.stringValue]
    else {
      return nil
    }
    guard let positionRange = Range<Position>(fromLSPDictionary: rangeDict),
      let textDocument = TextDocumentIdentifier(fromLSPDictionary: documentDict)
    else {
      return nil
    }

    self.init(
      title: title,
      actionString: actionString,
      positionRange: positionRange,
      textDocument: textDocument
    )
  }

  package init(
    title: String,
    actionString: String,
    positionRange: Range<Position>,
    textDocument: TextDocumentIdentifier
  ) {
    self.title = title
    self.actionString = actionString
    self.positionRange = positionRange
    self.textDocument = textDocument
  }

  package func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.title.stringValue: .string(title),
      CodingKeys.actionString.stringValue: .string(actionString),
      CodingKeys.positionRange.stringValue: positionRange.encodeToLSPAny(),
      CodingKeys.textDocument.stringValue: textDocument.encodeToLSPAny(),
    ])
  }
}
