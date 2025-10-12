//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import LanguageServerProtocol
import SourceKitD

/// Describes a kind of focused remarks supported by the compiler. Remarks should be exposed via
/// a flag which accepts a position in the document as a <line:column> pair and only emits
/// diagnostics relavant to that position (e.g. expressions or function bodies with source ranges that
/// contain the position).
package enum FocusedRemarksKind: String, CaseIterable, Codable {
  case showInferredTypes

  package var defaultTitle: String {
    switch self {
    case .showInferredTypes:
      return "Show Inferred Types"
    }
  }

  package func additionalCompilerArgs(line: Int, column: Int) -> [String] {
    switch self {
    case .showInferredTypes:
      return [
        "-Xfrontend",
        "-Rinferred-types-at",
        "-Xfrontend",
        "\(line):\(column)",
      ]
    }
  }
}

package struct FocusedRemarksCommand: SwiftCommand {
  package static let identifier: String = "focused.remarks.command"

  package let commandType: FocusedRemarksKind
  package var title: String
  package let position: Position
  package let textDocument: TextDocumentIdentifier

  package init(commandType: FocusedRemarksKind, position: Position, textDocument: TextDocumentIdentifier) {
    self.commandType = commandType
    self.position = position
    self.textDocument = textDocument
    self.title = commandType.defaultTitle
  }

  package init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard case .dictionary(let documentDict)? = dictionary[CodingKeys.textDocument.stringValue],
      case .string(let title)? = dictionary[CodingKeys.title.stringValue],
      case .dictionary(let positionDict)? = dictionary[CodingKeys.position.stringValue],
      case .string(let commandTypeString)? = dictionary[CodingKeys.commandType.stringValue]
    else {
      return nil
    }
    guard let position = Position(fromLSPDictionary: positionDict),
      let textDocument = TextDocumentIdentifier(fromLSPDictionary: documentDict),
      let commandType = FocusedRemarksKind(rawValue: commandTypeString)
    else {
      return nil
    }

    self.init(
      commandType: commandType,
      title: title,
      position: position,
      textDocument: textDocument
    )
  }

  package init(
    commandType: FocusedRemarksKind,
    title: String,
    position: Position,
    textDocument: TextDocumentIdentifier
  ) {
    self.commandType = commandType
    self.title = title
    self.position = position
    self.textDocument = textDocument
  }

  package func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.title.stringValue: .string(title),
      CodingKeys.position.stringValue: position.encodeToLSPAny(),
      CodingKeys.textDocument.stringValue: textDocument.encodeToLSPAny(),
      CodingKeys.commandType.stringValue: .string(commandType.rawValue),
    ])
  }
}
