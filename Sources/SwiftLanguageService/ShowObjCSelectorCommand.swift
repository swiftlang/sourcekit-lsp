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

/// Command to show the Objective-C selector for a Swift method marked with @objc.
package struct ShowObjCSelectorCommand: SwiftCommand {
  package static let identifier: String = "show.objc.selector.command"

  package var title = "Show Objective-C Selector"

  package var positionRange: Range<Position>
  package var textDocument: TextDocumentIdentifier

  package init(positionRange: Range<Position>, textDocument: TextDocumentIdentifier) {
    self.positionRange = positionRange
    self.textDocument = textDocument
  }

  package init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard case .dictionary(let documentDict)? = dictionary[CodingKeys.textDocument.stringValue],
      case .string(let title)? = dictionary[CodingKeys.title.stringValue],
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
      positionRange: positionRange,
      textDocument: textDocument
    )
  }

  package init(
    title: String,
    positionRange: Range<Position>,
    textDocument: TextDocumentIdentifier
  ) {
    self.title = title
    self.positionRange = positionRange
    self.textDocument = textDocument
  }

  package func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.title.stringValue: .string(title),
      CodingKeys.positionRange.stringValue: positionRange.encodeToLSPAny(),
      CodingKeys.textDocument.stringValue: textDocument.encodeToLSPAny(),
    ])
  }
}
