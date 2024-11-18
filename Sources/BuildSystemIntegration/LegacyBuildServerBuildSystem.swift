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
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import LanguageServerProtocolJSONRPC
import SKLogging
import SKOptions
import SwiftExtensions
import ToolchainRegistry

#if compiler(>=6.3)
#warning("We have had a one year transition period to the pull based build server. Consider removing this build server")
#endif

/// Bridges the gap between the legacy push-based BSP settings model and the new pull based BSP settings model.
///
/// On the one side, this type is a `BuiltInBuildSystem` that offers pull-based build settings. To serve these queries,
/// it communicates with an external BSP server that uses `build/sourceKitOptionsChanged` notifications to communicate
/// build settings.
///
/// This build server should be phased out in favor of the pull-based settings model described in
/// https://forums.swift.org/t/extending-functionality-of-build-server-protocol-with-sourcekit-lsp/74400
actor LegacyBuildServerBuildSystem: MessageHandler, BuiltInBuildSystem {
  private var buildServer: JSONRPCConnection?

  /// The queue on which all messages that originate from the build server are
  /// handled.
  ///
  /// These are requests and notifications sent *from* the build server,
  /// not replies from the build server.
  ///
  /// This ensures that messages from the build server are handled in the order
  /// they were received. Swift concurrency does not guarentee in-order
  /// execution of tasks.
  private let bspMessageHandlingQueue = AsyncQueue<Serial>()

  package let projectRoot: URL

  var fileWatchers: [FileSystemWatcher] = []

  let indexDatabasePath: URL?
  let indexStorePath: URL?

  package let connectionToSourceKitLSP: LocalConnection

  /// The build settings that have been received from the build server.
  private var buildSettings: [DocumentURI: TextDocumentSourceKitOptionsResponse] = [:]

  /// The files for which we have sent a `textDocument/registerForChanges` to the BSP server.
  private var urisRegisteredForChanges: Set<URI> = []

  init(
    projectRoot: URL,
    initializationData: InitializeBuildResponse,
    _ externalBuildSystemAdapter: ExternalBuildSystemAdapter
  ) async {
    self.projectRoot = projectRoot
    self.indexDatabasePath = nil
    self.indexStorePath = nil
    self.connectionToSourceKitLSP = LocalConnection(receiverName: "BuildSystemManager")
    await self.connectionToSourceKitLSP.start(handler: externalBuildSystemAdapter.messagesToSourceKitLSPHandler)
    await externalBuildSystemAdapter.changeMessageToSourceKitLSPHandler(to: self)
    self.buildServer = await externalBuildSystemAdapter.connectionToBuildServer
  }

  /// Handler for notifications received **from** the builder server, ie.
  /// the build server has sent us a notification.
  ///
  /// We need to notify the delegate about any updated build settings.
  package nonisolated func handle(_ params: some NotificationType) {
    logger.info(
      """
      Received notification from legacy BSP server:
      \(params.forLogging)
      """
    )
    bspMessageHandlingQueue.async {
      if let params = params as? OnBuildTargetDidChangeNotification {
        await self.handleBuildTargetsChanged(params)
      } else if let params = params as? FileOptionsChangedNotification {
        await self.handleFileOptionsChanged(params)
      }
    }
  }

  /// Handler for requests received **from** the build server.
  ///
  /// We currently can't handle any requests sent from the build server to us.
  package nonisolated func handle<R: RequestType>(
    _ params: R,
    id: RequestID,
    reply: @escaping (LSPResult<R.Response>) -> Void
  ) {
    logger.info(
      """
      Received request from legacy BSP server:
      \(params.forLogging)
      """
    )
    reply(.failure(ResponseError.methodNotFound(R.method)))
  }

  func handleBuildTargetsChanged(_ notification: OnBuildTargetDidChangeNotification) {
    connectionToSourceKitLSP.send(notification)
  }

  func handleFileOptionsChanged(_ notification: FileOptionsChangedNotification) async {
    let result = notification.updatedOptions
    let settings = TextDocumentSourceKitOptionsResponse(
      compilerArguments: result.options,
      workingDirectory: result.workingDirectory
    )
    await self.buildSettingsChanged(for: notification.uri, settings: settings)
  }

  /// Record the new build settings for the given document and inform the delegate
  /// about the changed build settings.
  private func buildSettingsChanged(for document: DocumentURI, settings: TextDocumentSourceKitOptionsResponse?) async {
    buildSettings[document] = settings
    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  package nonisolated var supportsPreparation: Bool { false }

  package func buildTargets(request: WorkspaceBuildTargetsRequest) async throws -> WorkspaceBuildTargetsResponse {
    return WorkspaceBuildTargetsResponse(targets: [
      BuildTarget(
        id: .dummy,
        displayName: "BuildServer",
        baseDirectory: nil,
        tags: [.test],
        capabilities: BuildTargetCapabilities(),
        // Be conservative with the languages that might be used in the target. SourceKit-LSP doesn't use this property.
        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
        dependencies: []
      )
    ])
  }

  package func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
    guard request.targets.contains(.dummy) else {
      return BuildTargetSourcesResponse(items: [])
    }
    return BuildTargetSourcesResponse(items: [
      SourcesItem(
        target: .dummy,
        sources: [SourceItem(uri: DocumentURI(self.projectRoot), kind: .directory, generated: false)]
      )
    ])
  }

  package func didChangeWatchedFiles(notification: OnWatchedFilesDidChangeNotification) {}

  package func prepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    throw PrepareNotSupportedError()
  }

  package func sourceKitOptions(
    request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    // Support the pre Swift 6.1 build settings workflow where SourceKit-LSP registers for changes for a file and then
    // expects updates to those build settings to get pushed to SourceKit-LSP with `FileOptionsChangedNotification`.
    // We do so by registering for changes when requesting build settings for a document for the first time. We never
    // unregister for changes. The expectation is that all BSP servers migrate to the `SourceKitOptionsRequest` soon,
    // which renders this code path dead.
    let uri = request.textDocument.uri
    if urisRegisteredForChanges.insert(uri).inserted {
      let request = RegisterForChanges(uri: uri, action: .register)
      _ = self.buildServer?.send(request) { result in
        if let error = result.failure {
          logger.error("Error registering \(request.uri): \(error.forLogging)")

          Task {
            // BuildServer registration failed, so tell our delegate that no build
            // settings are available.
            await self.buildSettingsChanged(for: request.uri, settings: nil)
          }
        }
      }
    }

    guard let buildSettings = buildSettings[uri] else {
      return nil
    }

    return TextDocumentSourceKitOptionsResponse(
      compilerArguments: buildSettings.compilerArguments,
      workingDirectory: buildSettings.workingDirectory
    )
  }

  package func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }
}
