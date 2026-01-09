//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Csourcekitd
@_spi(SourceKitLSP) package import LanguageServerProtocol
import SourceKitD

package struct SemanticRefactorCommand: SwiftCommand {
  typealias Response = SemanticRefactoring

  package static let identifier: String = "semantic.refactor.command"

  /// The name of this refactoring action.
  package var title: String

  /// The sourcekitd identifier of the refactoring action.
  package var actionString: String

  /// The range to refactor.
  package var positionRange: Range<Position>

  /// The text document related to the refactoring action.
  package var textDocument: TextDocumentIdentifier

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

  /// Maps the SourceKit action string to an appropriate LSP CodeActionKind.
  ///
  /// SourceKit uses identifiers like `source.refactoring.kind.extract.expr`
  /// which this property maps to LSP kinds like `refactor.extract`.
  package var lspKind: CodeActionKind {
    if actionString.contains(".extract.") || actionString.contains(".move.") {
      return .refactorExtract
    } else if actionString.contains(".inline.") {
      return .refactorInline
    } else if actionString.contains(".convert.") {
      return .refactorRewrite
    } else {
      return .refactor
    }
  }
}

extension Array where Element == SemanticRefactorCommand {
  init?(
    array: SKDResponseArray?,
    range: Range<Position>,
    textDocument: TextDocumentIdentifier,
    _ keys: sourcekitd_api_keys,
    _ api: sourcekitd_api_functions_t
  ) {
    guard let results = array else {
      return nil
    }
    var commands: [SemanticRefactorCommand] = []
    // swift-format-ignore: ReplaceForEachWithForLoop
    // Reference is to `SKDResponseArray.forEach`, not `Array.forEach`.
    results.forEach { _, value in
      if let name: String = value[keys.actionName],
        let actionuid: sourcekitd_api_uid_t = value[keys.actionUID],
        let ptr = api.uid_get_string_ptr(actionuid)
      {
        let actionName = String(cString: ptr)
        guard !actionName.hasPrefix("source.refactoring.kind.rename.") else {
          return true
        }
        guard !supersededSourcekitdRefactoringActions.contains(actionName) else {
          return true
        }
        commands.append(
          SemanticRefactorCommand(
            title: name,
            actionString: actionName,
            positionRange: range,
            textDocument: textDocument
          )
        )
      }
      return true
    }
    self = commands
  }
}
