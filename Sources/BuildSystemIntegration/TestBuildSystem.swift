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

import BuildServerProtocol
import LanguageServerProtocol
import SKOptions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath

/// Build system to be used for testing BuildSystem and BuildSystemDelegate functionality with SourceKitLSPServer
/// and other components.
package actor TestBuildSystem: BuiltInBuildSystem {
  package static func projectRoot(for workspaceFolder: AbsolutePath, options: SourceKitLSPOptions) -> AbsolutePath? {
    return workspaceFolder
  }

  package let projectRoot: AbsolutePath
  package let indexStorePath: AbsolutePath? = nil
  package let indexDatabasePath: AbsolutePath? = nil

  private let connectionToSourceKitLSP: any Connection

  /// Build settings by file.
  private var buildSettingsByFile: [DocumentURI: SourceKitOptionsResponse] = [:]

  package func setBuildSettings(for uri: DocumentURI, to buildSettings: SourceKitOptionsResponse?) {
    buildSettingsByFile[uri] = buildSettings
    connectionToSourceKitLSP.send(DidChangeBuildTargetNotification(changes: nil))
  }

  package nonisolated var supportsPreparation: Bool { false }

  package init(
    projectRoot: AbsolutePath,
    connectionToSourceKitLSP: any Connection
  ) {
    self.projectRoot = projectRoot
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
  }

  package func buildTargets(request: BuildTargetsRequest) async throws -> BuildTargetsResponse {
    return BuildTargetsResponse(targets: [
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

  package func didChangeWatchedFiles(notification: BuildServerProtocol.DidChangeWatchedFilesNotification) async {}

  package func prepare(request: PrepareTargetsRequest) async throws -> VoidResponse {
    throw PrepareNotSupportedError()
  }

  package func sourceKitOptions(request: SourceKitOptionsRequest) async throws -> SourceKitOptionsResponse? {
    return buildSettingsByFile[request.textDocument.uri]
  }

  package func waitForUpBuildSystemUpdates(request: WaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }

  package func topologicalSort(of targets: [BuildTargetIdentifier]) -> [BuildTargetIdentifier]? {
    return nil
  }
}
