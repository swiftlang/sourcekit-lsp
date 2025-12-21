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
  /// Gets the Objective-C selector for the method at the given position.
  ///
  /// Uses the `source.request.objc.selector` sourcekitd request directly
  /// to retrieve the selector string for @objc methods.
  func showObjCSelector(
    _ command: ShowObjCSelectorCommand
  ) async throws -> LSPAny {
    let keys = self.keys

    let uri = command.textDocument.uri
    let snapshot = try self.documentManager.latestSnapshot(uri)
    let position = command.positionRange.lowerBound
    let offset = snapshot.utf8Offset(of: position)

    let skreq = sourcekitd.dictionary([
      keys.sourceFile: uri.pseudoPath,
      keys.offset: offset,
      keys.compilerArgs: await self.compileCommand(for: uri, fallbackAfterTimeout: true)?.compilerArgs
        as [any SKDRequestValue]?,
    ])

    let dict = try await send(sourcekitdRequest: \.objcSelector, skreq, snapshot: snapshot)

    guard let selector: String = dict[keys.text] else {
      throw ResponseError.unknown("Could not retrieve Objective-C selector at cursor position")
    }

    if let sourceKitLSPServer {
      sourceKitLSPServer.sendNotificationToClient(
        ShowMessageNotification(type: .info, message: selector)
      )
    }

    return .string(selector)
  }
}
