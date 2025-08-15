import Foundation
package import LanguageServerProtocol
import SKLogging
import SKUtilities
import SwiftExtensions

package actor OnDiskDocumentManager {
  private weak var sourceKitLSPServer: SourceKitLSPServer?
  private var openSnapshots: [DocumentURI: DocumentSnapshot]

  fileprivate init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
    openSnapshots = [:]
  }

  /// Retrieves the ``LanguageService`` for a given ``DocumentURI`` and ``Language``.
  package func languageService(for uri: DocumentURI, _ language: Language) async throws -> LanguageService {
    guard let sourceKitLSPServer,
      let workspace = await sourceKitLSPServer.workspaceForDocument(uri: uri),
      let languageService = await sourceKitLSPServer.languageService(for: uri, language, in: workspace)
    else {
      throw ResponseError.unknown("Unable to find language service for URI: \(uri)")
    }
    return languageService
  }

  /// Opens a dummy ``DocumentSnapshot`` with contents from disk for a given ``DocumentURI`` and ``Language``.
  ///
  /// The snapshot will remain cached until ``closeAllDocuments()`` is called.
  package func open(uri: DocumentURI, language: Language) async throws -> DocumentSnapshot {
    guard let fileURL = uri.fileURL else {
      throw ResponseError.unknown("Cannot create snapshot with on-disk contents for non-file URI \(uri.forLogging)")
    }

    if let cachedSnapshot = openSnapshots[uri] {
      return cachedSnapshot
    }

    let snapshot = DocumentSnapshot(
      uri: try DocumentURI(filePath: "\(UUID().uuidString)/\(fileURL.filePath)", isDirectory: false),
      language: language,
      version: 0,
      lineTable: LineTable(try String(contentsOf: fileURL, encoding: .utf8))
    )
    try await languageService(for: uri, language).openDocumentOnDisk(snapshot: snapshot, originalFile: uri)
    openSnapshots[uri] = snapshot
    return snapshot
  }

  /// Close all of the ``DocumentSnapshot``s that were opened by this ``OnDiskDocumentManager``.
  package func closeAllDocuments() async {
    for snapshot in openSnapshots.values {
      await orLog("Closing snapshot from on-disk contents: \(snapshot.uri.forLogging)") {
        try await languageService(for: snapshot.uri, snapshot.language).closeDocumentOnDisk(snapshot: snapshot)
      }
    }
    openSnapshots = [:]
  }
}

package extension SourceKitLSPServer {
  nonisolated(nonsending) func withOnDiskDocumentManager<T>(
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
