//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildSystemIntegration
import Foundation
import LanguageServerProtocol
import SKLogging
import SKUtilities
import SwiftExtensions

extension SwiftLanguageService {
  /// Open a unique dummy document in sourcekitd that has the contents of the file on disk for `uri` but an arbitrary
  /// URI which doesn't exist on disk. Invoke `body` with a snapshot that contains the on-disk document contents and has
  /// that dummy URI as well as build settings that were inferred from `uri` but have that URI replaced with the dummy
  /// URI. Close the document in sourcekit after `body` has finished.
  func withSnapshotFromDiskOpenedInSourcekitd<Result: Sendable>(
    uri: DocumentURI,
    fallbackSettingsAfterTimeout: Bool,
    body: (_ snapshot: DocumentSnapshot, _ patchedCompileCommand: SwiftCompileCommand?) async throws -> Result
  ) async throws -> Result {
    guard let fileURL = uri.fileURL else {
      throw ResponseError.unknown("Cannot create snapshot with on-disk contents for non-file URI \(uri.forLogging)")
    }
    let snapshot = DocumentSnapshot(
      uri: try DocumentURI(filePath: "\(UUID().uuidString)/\(fileURL.filePath)", isDirectory: false),
      language: .swift,
      version: 0,
      lineTable: LineTable(try String(contentsOf: fileURL, encoding: .utf8))
    )
    let patchedCompileCommand: SwiftCompileCommand? =
      if let buildSettings = await self.buildSettings(
        for: uri,
        fallbackAfterTimeout: fallbackSettingsAfterTimeout
      ) {
        SwiftCompileCommand(buildSettings.patching(newFile: snapshot.uri, originalFile: uri))
      } else {
        nil
      }

    _ = try await sendSourcekitdRequest(
      self.openDocumentSourcekitdRequest(snapshot: snapshot, compileCommand: patchedCompileCommand),
      fileContents: snapshot.text
    )
    let result: Swift.Result<Result, Error>
    do {
      result = .success(try await body(snapshot, patchedCompileCommand))
    } catch {
      result = .failure(error)
    }
    await orLog("Close helper document '\(snapshot.uri)' for cursorInfoFromDisk") {
      _ = try await sendSourcekitdRequest(
        self.closeDocumentSourcekitdRequest(uri: snapshot.uri),
        fileContents: snapshot.text
      )
    }
    return try result.get()
  }
}
