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

  package weak var delegate: BuildSystemDelegate?

  private weak var messageHandler: BuiltInBuildSystemMessageHandler?

  package func setDelegate(_ delegate: BuildSystemDelegate?) async {
    self.delegate = delegate
  }

  /// Build settings by file.
  private var buildSettingsByFile: [DocumentURI: SourceKitOptionsResponse] = [:]

  /// Files currently being watched by our delegate.
  private var watchedFiles: Set<DocumentURI> = []

  package func setBuildSettings(for uri: DocumentURI, to buildSettings: SourceKitOptionsResponse?) async {
    buildSettingsByFile[uri] = buildSettings
    await self.messageHandler?.sendNotificationToSourceKitLSP(DidChangeBuildTargetNotification(changes: nil))
  }

  package nonisolated var supportsPreparation: Bool { false }

  package init(
    projectRoot: AbsolutePath,
    messageHandler: any BuiltInBuildSystemMessageHandler
  ) {
    self.projectRoot = projectRoot
    self.messageHandler = messageHandler
  }

  package func sourceKitOptions(request: SourceKitOptionsRequest) async throws -> SourceKitOptionsResponse? {
    return buildSettingsByFile[request.textDocument.uri]
  }

  package func defaultLanguage(for document: DocumentURI) async -> Language? {
    return nil
  }

  package func toolchain(for uri: DocumentURI, _ language: Language) async -> Toolchain? {
    return nil
  }

  package func inverseSources(request: InverseSourcesRequest) -> InverseSourcesResponse {
    return InverseSourcesResponse(targets: [BuildTargetIdentifier.dummy])
  }

  package func prepare(
    targets: [BuildTargetIdentifier],
    logMessageToIndexLog: @escaping @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void
  ) async throws {
    throw PrepareNotSupportedError()
  }

  package func scheduleBuildGraphGeneration() {}

  package func waitForUpToDateBuildGraph() async {}

  package func topologicalSort(of targets: [BuildTargetIdentifier]) -> [BuildTargetIdentifier]? {
    return nil
  }

  package func targets(dependingOn targets: [BuildTargetIdentifier]) -> [BuildTargetIdentifier]? {
    return nil
  }

  package func registerForChangeNotifications(for uri: DocumentURI) async {
    watchedFiles.insert(uri)
  }

  package func unregisterForChangeNotifications(for uri: DocumentURI) {
    watchedFiles.remove(uri)
  }

  package func didChangeWatchedFiles(notification: BuildServerProtocol.DidChangeWatchedFilesNotification) async {}

  package func sourceFiles() async -> [SourceFileInfo] {
    return []
  }

  package func addSourceFilesDidChangeCallback(_ callback: @escaping () async -> Void) async {}
}
