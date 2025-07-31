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

import BuildSystemIntegration
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import SKLogging
import SKUtilities
import SwiftExtensions

/// A cache of symbol graphs and their associated snapshots opened in sourcekitd. Any opened documents will be
/// closed when the cache is de-initialized.
///
/// Used by `textDocument/doccDocumentation` requests to retrieve symbol graphs for files that are not currently
/// open in the editor. This allows for retrieving multiple symbol graphs from the same file without having
/// to re-open and parse the syntax tree every time.
actor SymbolGraphCache: Sendable {
  private weak var sourceKitLSPServer: SourceKitLSPServer?
  private var openSnapshots: [DocumentURI: (snapshot: DocumentSnapshot, patchedCompileCommand: SwiftCompileCommand?)]

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.openSnapshots = [:]
  }

  /// Open a unique dummy document in sourcekitd that has the contents of the file on disk for uri, but an arbitrary
  /// URI which doesn't exist on disk. Return the symbol graph from sourcekitd.
  ///
  /// The document will be retained until ``DocCSymbolGraphCache`` is de-initialized. This will avoid parsing the same
  /// document multiple times if more than one symbol needs to be looked up.
  ///
  /// - Parameter symbolLocation: The location of a symbol to find the symbol graph for.
  /// - Returns: The symbol graph for this location, if any.
  func fetchSymbolGraph(at symbolLocation: SymbolLocation) async throws -> String? {
    let swiftLanguageService = try await swiftLanguageService(for: symbolLocation.documentUri)
    let (snapshot, patchedCompileCommand) = try await swiftLanguageService.openSnapshotFromDiskOpenedInSourcekitd(
      uri: symbolLocation.documentUri,
      fallbackSettingsAfterTimeout: false
    )
    return try await swiftLanguageService.cursorInfo(
      snapshot,
      compileCommand: patchedCompileCommand,
      Range(snapshot.position(of: symbolLocation)),
      includeSymbolGraph: true
    ).symbolGraph
  }

  private func swiftLanguageService(for uri: DocumentURI) async throws -> SwiftLanguageService {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: uri),
      let languageService = await sourceKitLSPServer.languageService(for: uri, .swift, in: workspace),
      let swiftLanguageService = languageService as? SwiftLanguageService
    else {
      throw ResponseError.internalError("Unable to find SwiftLanguageService for \(uri)")
    }
    return swiftLanguageService
  }

  deinit {
    guard let sourceKitLSPServer else {
      return
    }

    let documentsToClose = openSnapshots.values
    Task {
      for (snapshot, _) in documentsToClose {
        guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: snapshot.uri),
          let languageService = await sourceKitLSPServer.languageService(for: snapshot.uri, .swift, in: workspace),
          let swiftLanguageService = languageService as? SwiftLanguageService
        else {
          logger.log("Unable to find SwiftLanguageService to close helper document \(snapshot.uri.forLogging)")
          return
        }
        await swiftLanguageService.closeSnapshotFromDiskOpenedInSourcekitd(snapshot: snapshot)
      }
    }
  }
}

fileprivate extension SwiftLanguageService {
  func openSnapshotFromDiskOpenedInSourcekitd(
    uri: DocumentURI,
    fallbackSettingsAfterTimeout: Bool,
  ) async throws -> (snapshot: DocumentSnapshot, patchedCompileCommand: SwiftCompileCommand?) {
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

    _ = try await send(
      sourcekitdRequest: \.editorOpen,
      self.openDocumentSourcekitdRequest(snapshot: snapshot, compileCommand: patchedCompileCommand),
      snapshot: snapshot
    )

    return (snapshot, patchedCompileCommand)
  }

  func closeSnapshotFromDiskOpenedInSourcekitd(snapshot: DocumentSnapshot) async {
    await orLog("Close helper document '\(snapshot.uri)'") {
      _ = try await send(
        sourcekitdRequest: \.editorClose,
        self.closeDocumentSourcekitdRequest(uri: snapshot.uri),
        snapshot: snapshot
      )
    }
  }
}
