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

@_spi(SourceKitLSP) import BuildServerProtocol
package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SwiftExtensions
import ToolchainRegistry
import ToolsProtocolsSwiftExtensions

/// The details necessary to create a `BuildServerAdapter`.
package struct BuildServerSpec {
  package enum Kind {
    case externalBuildServer
    case jsonCompilationDatabase
    case fixedCompilationDatabase
    case swiftPM
    case injected(
      @Sendable (_ projectRoot: URL, _ connectionToSourceKitLSP: any Connection) async -> any Connection
    )
  }

  package var kind: Kind

  /// The folder that best describes the root of the project that this build server handles.
  package var projectRoot: URL

  /// The main path that provides the build server configuration.
  package var configPath: URL

  package init(kind: BuildServerSpec.Kind, projectRoot: URL, configPath: URL) {
    self.kind = kind
    self.projectRoot = projectRoot
    self.configPath = configPath
  }
}

/// A type that outwardly acts as a BSP build server and internally uses a `BuiltInBuildServer` to satisfy the requests.
actor BuiltInBuildServerAdapter: QueueBasedMessageHandler {
  let messageHandlingHelper = QueueBasedMessageHandlerHelper(
    signpostLoggingCategory: "build-server-message-handling",
    createLoggingScope: false
  )

  /// The queue on which all messages from SourceKit-LSP (or more specifically `BuildServerManager`) are handled.
  package let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()

  /// The underlying build server
  private var underlyingBuildServer: any BuiltInBuildServer

  /// The connection with which messages are sent to `BuildServerManager`.
  private let connectionToSourceKitLSP: LocalConnection

  private let buildServerHooks: BuildServerHooks

  /// Create a `BuiltInBuildServerAdapter` form an existing `BuiltInBuildServer` and connection to communicate messages
  /// from the build server to SourceKit-LSP.
  init(
    underlyingBuildServer: any BuiltInBuildServer,
    connectionToSourceKitLSP: LocalConnection,
    buildServerHooks: BuildServerHooks
  ) {
    self.underlyingBuildServer = underlyingBuildServer
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
    self.buildServerHooks = buildServerHooks
  }

  deinit {
    connectionToSourceKitLSP.close()
  }

  private func initialize(request: InitializeBuildRequest) async -> InitializeBuildResponse {
    return InitializeBuildResponse(
      displayName: "\(type(of: underlyingBuildServer))",
      version: "",
      bspVersion: "2.2.0",
      capabilities: BuildServerCapabilities(),
      dataKind: .sourceKit,
      data: SourceKitInitializeBuildResponseData(
        indexDatabasePath: await orLog("getting index database file path") {
          try await underlyingBuildServer.indexDatabasePath?.filePath
        },
        indexStorePath: await orLog("getting index store file path") {
          try await underlyingBuildServer.indexStorePath?.filePath
        },
        outputPathsProvider: underlyingBuildServer.supportsPreparationAndOutputPaths,
        prepareProvider: underlyingBuildServer.supportsPreparationAndOutputPaths,
        sourceKitOptionsProvider: true,
        watchers: await underlyingBuildServer.fileWatchers
      ).encodeToLSPAny()
    )
  }

  package func handle(notification: some NotificationType) async {
    switch notification {
    case is OnBuildExitNotification:
      break
    case is OnBuildInitializedNotification:
      break
    case let notification as OnWatchedFilesDidChangeNotification:
      await self.underlyingBuildServer.didChangeWatchedFiles(notification: notification)
    default:
      logger.error("Ignoring unknown notification \(type(of: notification).method) from SourceKit-LSP")
    }
  }

  func handle<Request: RequestType>(
    request: Request,
    id: RequestID,
    reply: @Sendable @escaping (Result<Request.Response, any Error>) -> Void
  ) async {
    let request = RequestAndReply(request, reply: reply)
    await buildServerHooks.preHandleRequest?(request.params)
    switch request {
    case let request as RequestAndReply<BuildShutdownRequest>:
      await request.reply { VoidResponse() }
    case let request as RequestAndReply<BuildTargetPrepareRequest>:
      await request.reply { try await underlyingBuildServer.prepare(request: request.params) }
    case let request as RequestAndReply<BuildTargetSourcesRequest>:
      await request.reply { try await underlyingBuildServer.buildTargetSources(request: request.params) }
    case let request as RequestAndReply<InitializeBuildRequest>:
      await request.reply { await self.initialize(request: request.params) }
    case let request as RequestAndReply<TextDocumentSourceKitOptionsRequest>:
      await request.reply { try await underlyingBuildServer.sourceKitOptions(request: request.params) }
    case let request as RequestAndReply<WorkspaceBuildTargetsRequest>:
      await request.reply { try await underlyingBuildServer.buildTargets(request: request.params) }
    case let request as RequestAndReply<WorkspaceWaitForBuildSystemUpdatesRequest>:
      await request.reply { await underlyingBuildServer.waitForBuildSystemUpdates(request: request.params) }
    default:
      await request.reply { throw ResponseError.methodNotFound(Request.method) }
    }
  }
}
