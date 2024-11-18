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
import LanguageServerProtocolExtensions
import SKLogging
import SKOptions
import SwiftExtensions
import ToolchainRegistry

#if compiler(>=6)
package import Foundation
#else
import Foundation
#endif

/// The details necessary to create a `BuildSystemAdapter`.
package struct BuildSystemSpec {
  package enum Kind {
    case buildServer
    case compilationDatabase
    case swiftPM
    case testBuildSystem
  }

  package var kind: Kind

  package var projectRoot: URL

  package init(kind: BuildSystemSpec.Kind, projectRoot: URL) {
    self.kind = kind
    self.projectRoot = projectRoot
  }
}

/// A type that outwardly acts as a BSP build server and internally uses a `BuiltInBuildSystem` to satisfy the requests.
actor BuiltInBuildSystemAdapter: QueueBasedMessageHandler {
  let messageHandlingHelper = QueueBasedMessageHandlerHelper(
    signpostLoggingCategory: "build-system-message-handling",
    createLoggingScope: false
  )

  /// The queue on which all messages from SourceKit-LSP (or more specifically `BuildSystemManager`) are handled.
  package let messageHandlingQueue = AsyncQueue<BuildSystemMessageDependencyTracker>()

  /// The underlying build system
  private var underlyingBuildSystem: BuiltInBuildSystem

  /// The connection with which messages are sent to `BuildSystemManager`.
  private let connectionToSourceKitLSP: LocalConnection

  private let buildSystemTestHooks: BuildSystemTestHooks

  /// If the underlying build system is a `TestBuildSystem`, return it. Otherwise, `nil`
  ///
  /// - Important: For testing purposes only.
  var testBuildSystem: TestBuildSystem? {
    return underlyingBuildSystem as? TestBuildSystem
  }

  /// Create a `BuiltInBuildSystemAdapter` form an existing `BuiltInBuildSystem` and connection to communicate messages
  /// from the build system to SourceKit-LSP.
  init(
    underlyingBuildSystem: BuiltInBuildSystem,
    connectionToSourceKitLSP: LocalConnection,
    buildSystemTestHooks: BuildSystemTestHooks
  ) {
    self.underlyingBuildSystem = underlyingBuildSystem
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
    self.buildSystemTestHooks = buildSystemTestHooks
  }

  deinit {
    connectionToSourceKitLSP.close()
  }

  private func initialize(request: InitializeBuildRequest) async -> InitializeBuildResponse {
    return InitializeBuildResponse(
      displayName: "\(type(of: underlyingBuildSystem))",
      version: "",
      bspVersion: "2.2.0",
      capabilities: BuildServerCapabilities(),
      dataKind: .sourceKit,
      data: SourceKitInitializeBuildResponseData(
        indexDatabasePath: await orLog("getting index database file path") {
          try await underlyingBuildSystem.indexDatabasePath?.filePath
        },
        indexStorePath: await orLog("getting index store file path") {
          try await underlyingBuildSystem.indexStorePath?.filePath
        },
        watchers: await underlyingBuildSystem.fileWatchers,
        prepareProvider: underlyingBuildSystem.supportsPreparation,
        sourceKitOptionsProvider: true
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
      await self.underlyingBuildSystem.didChangeWatchedFiles(notification: notification)
    default:
      logger.error("Ignoring unknown notification \(type(of: notification).method) from SourceKit-LSP")
    }
  }

  func handle<Request: RequestType>(
    request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) async {
    let request = RequestAndReply(request, reply: reply)
    await buildSystemTestHooks.handleRequest?(request.params)
    switch request {
    case let request as RequestAndReply<BuildShutdownRequest>:
      await request.reply { VoidResponse() }
    case let request as RequestAndReply<BuildTargetPrepareRequest>:
      await request.reply { try await underlyingBuildSystem.prepare(request: request.params) }
    case let request as RequestAndReply<BuildTargetSourcesRequest>:
      await request.reply { try await underlyingBuildSystem.buildTargetSources(request: request.params) }
    case let request as RequestAndReply<InitializeBuildRequest>:
      await request.reply { await self.initialize(request: request.params) }
    case let request as RequestAndReply<TextDocumentSourceKitOptionsRequest>:
      await request.reply { try await underlyingBuildSystem.sourceKitOptions(request: request.params) }
    case let request as RequestAndReply<WorkspaceBuildTargetsRequest>:
      await request.reply { try await underlyingBuildSystem.buildTargets(request: request.params) }
    case let request as RequestAndReply<WorkspaceWaitForBuildSystemUpdatesRequest>:
      await request.reply { await underlyingBuildSystem.waitForBuildSystemUpdates(request: request.params) }
    default:
      await request.reply { throw ResponseError.methodNotFound(Request.method) }
    }
  }
}
