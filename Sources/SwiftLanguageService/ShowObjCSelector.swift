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

@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP

extension SwiftLanguageService {
  /// The Objective-C selector of the declaration at `position`, or `nil` if it isn't exposed to Objective-C or the
  /// toolchain doesn't know the request.
  func objcSelector(_ uri: DocumentURI, at position: Position) async -> String? {
    return await orLog("Getting Objective-C selector") {
      let snapshot = try await self.latestSnapshot(for: uri)
      let skreq = sourcekitd.dictionary([
        keys.offset: snapshot.utf8Offset(of: position),
        keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
        keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
        keys.compilerArgs: await self.compileCommand(for: uri, fallbackAfterTimeout: true)?.compilerArgs
          as [any SKDRequestValue]?,
      ])
      let dict = try await self.send(sourcekitdRequest: \.objcSelector, skreq, snapshot: snapshot)
      return dict[keys.text] as String?
    }
  }

  func showObjCSelector(_ command: ShowObjCSelectorCommand) -> LSPAny {
    sourceKitLSPServer?.sendNotificationToClient(ShowMessageNotification(type: .info, message: command.selector))
    return .string(command.selector)
  }
}
