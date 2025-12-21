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

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP

extension SwiftLanguageService {
  /// Executes the refactoring-based copy and extracts the selector string without applying edits.
  func showObjCSelector(
    _ command: ShowObjCSelectorCommand
  ) async throws -> LSPAny {
    let refactorCommand = SemanticRefactorCommand(
      title: command.title,
      actionString: command.actionString,
      positionRange: command.positionRange,
      textDocument: command.textDocument
    )

    let semanticRefactor = try await self.refactoring(refactorCommand)

    guard let edit = semanticRefactor.edit.changes?.first?.value.first else {
      throw ResponseError.unknown("No selector found at cursor position")
    }

    let prefix = "// Objective-C Selector: "
    if let range = edit.newText.range(of: prefix) {
      let selector = String(edit.newText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
      if let sourceKitLSPServer {
        // Notify with just the selector text (no prefix, no buttons).
        sourceKitLSPServer.sendNotificationToClient(
          ShowMessageNotification(type: .info, message: selector)
        )
      }
      return .string(selector)
    }

    throw ResponseError.unknown("Could not extract selector from refactoring result")
  }
}
