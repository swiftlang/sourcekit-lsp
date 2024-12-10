//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if compiler(>=6)
package import BuildServerProtocol
package import Foundation
package import LanguageServerProtocol
import SKOptions
import ToolchainRegistry
#else
import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import SKOptions
import ToolchainRegistry
#endif

/// Build system to be used for testing BuildSystem and BuildSystemDelegate functionality with SourceKitLSPServer
/// and other components.
package actor TestBuildSystem: BuiltInBuildSystem {
  package let projectRoot: URL

  package let fileWatchers: [FileSystemWatcher] = []

  package let indexStorePath: URL? = nil
  package let indexDatabasePath: URL? = nil

  private let connectionToSourceKitLSP: any Connection

  /// Build settings by file.
  private var buildSettingsByFile: [DocumentURI: TextDocumentSourceKitOptionsResponse] = [:]

  package func setBuildSettings(for uri: DocumentURI, to buildSettings: TextDocumentSourceKitOptionsResponse?) {
    buildSettingsByFile[uri] = buildSettings
    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  package nonisolated var supportsPreparation: Bool { false }

  package init(
    projectRoot: URL,
    connectionToSourceKitLSP: any Connection
  ) {
    self.projectRoot = projectRoot
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
  }

  package func buildTargets(request: WorkspaceBuildTargetsRequest) async throws -> WorkspaceBuildTargetsResponse {
    return WorkspaceBuildTargetsResponse(targets: [
      BuildTarget(
        id: .dummy,
        displayName: nil,
        baseDirectory: nil,
        tags: [],
        capabilities: BuildTargetCapabilities(),
        languageIds: [],
        dependencies: []
      )
    ])
  }

  package func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
    return BuildTargetSourcesResponse(items: [
      SourcesItem(
        target: .dummy,
        sources: buildSettingsByFile.keys.map { SourceItem(uri: $0, kind: .file, generated: false) }
      )
    ])
  }

  package func didChangeWatchedFiles(notification: OnWatchedFilesDidChangeNotification) async {}

  package func prepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    throw PrepareNotSupportedError()
  }

  package func sourceKitOptions(
    request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    return buildSettingsByFile[request.textDocument.uri]
  }

  package func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }
}
