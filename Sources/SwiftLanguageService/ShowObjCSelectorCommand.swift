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

package struct ShowObjCSelectorCommand: SwiftCommand {
  package static let identifier: String = "show.objc.selector.command"

  package var title = "Show Objective-C Selector"
  package var actionString = "source.refactoring.kind.copy.objc.selector"

  package var positionRange: Range<Position>
  package var textDocument: LanguageServerProtocol.TextDocumentIdentifier

  package init(positionRange: Range<Position>, textDocument: LanguageServerProtocol.TextDocumentIdentifier) {
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
      let textDocument = LanguageServerProtocol.TextDocumentIdentifier(fromLSPDictionary: documentDict)
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
    textDocument: LanguageServerProtocol.TextDocumentIdentifier
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
