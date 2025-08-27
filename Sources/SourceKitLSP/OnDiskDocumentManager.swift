//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import BuildServerIntegration
import Foundation
package import LanguageServerProtocol
import SKLogging
import SKUtilities
import SwiftExtensions

package actor OnDiskDocumentManager {
  private let sourceKitLSPServer: SourceKitLSPServer
  private var openSnapshots:
    [DocumentURI: (snapshot: DocumentSnapshot, buildSettings: FileBuildSettings, workspace: Workspace)]

  fileprivate init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
    openSnapshots = [:]
  }

  /// Opens a dummy ``DocumentSnapshot`` with contents from disk for a given ``DocumentURI`` and ``Language``.
  ///
  /// The snapshot will remain cached until ``closeAllDocuments()`` is called.
  package func open(
    uri: DocumentURI,
    language: Language,
    in workspace: Workspace
  ) async throws -> (snapshot: DocumentSnapshot, buildSettings: FileBuildSettings) {
    guard let fileURL = uri.fileURL else {
      throw ResponseError.unknown("Cannot create snapshot with on-disk contents for non-file URI \(uri.forLogging)")
    }

    if let cachedSnapshot = openSnapshots[uri] {
      return (cachedSnapshot.snapshot, cachedSnapshot.buildSettings)
    }

    let snapshot = DocumentSnapshot(
      uri: try DocumentURI(filePath: "\(UUID().uuidString)/\(fileURL.filePath)", isDirectory: false),
      language: language,
      version: 0,
      lineTable: LineTable(try String(contentsOf: fileURL, encoding: .utf8))
    )
    let languageService = try await sourceKitLSPServer.primaryLanguageService(for: uri, language, in: workspace)

    let originalBuildSettings = await workspace.buildServerManager.buildSettingsInferredFromMainFile(
      for: uri,
      language: language,
      fallbackAfterTimeout: false
    )
    guard let originalBuildSettings else {
      throw ResponseError.unknown("Failed to infer build settings for \(uri)")
    }
    let patchedBuildSettings = originalBuildSettings.patching(newFile: snapshot.uri, originalFile: uri)
    try await languageService.openOnDiskDocument(snapshot: snapshot, buildSettings: patchedBuildSettings)
    openSnapshots[uri] = (snapshot, patchedBuildSettings, workspace)
    return (snapshot, patchedBuildSettings)
  }

  /// Close all of the ``DocumentSnapshot``s that were opened by this ``OnDiskDocumentManager``.
  fileprivate func closeAllDocuments() async {
    for (snapshot, _, workspace) in openSnapshots.values {
      await orLog("Closing snapshot from on-disk contents: \(snapshot.uri.forLogging)") {
        let languageService =
          try await sourceKitLSPServer.primaryLanguageService(for: snapshot.uri, snapshot.language, in: workspace)
        try await languageService.closeOnDiskDocument(uri: snapshot.uri)
      }
    }
    openSnapshots = [:]
  }
}

package extension SourceKitLSPServer {
  nonisolated func withOnDiskDocumentManager<T>(
    _ body: (OnDiskDocumentManager) async throws -> T
  ) async rethrows -> T {
    let manager = OnDiskDocumentManager(sourceKitLSPServer: self)
    do {
      let result = try await body(manager)
      await manager.closeAllDocuments()
      return result
    } catch {
      await manager.closeAllDocuments()
      throw error
    }
  }
}
