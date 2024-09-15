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
import SKLogging
import SKOptions
import SKSupport
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

package enum BuildSystemKind {
  case buildServer(projectRoot: AbsolutePath)
  case compilationDatabase(projectRoot: AbsolutePath)
  case swiftPM(projectRoot: AbsolutePath)
  case testBuildSystem(projectRoot: AbsolutePath)

  package var projectRoot: AbsolutePath {
    switch self {
    case .buildServer(let projectRoot): return projectRoot
    case .compilationDatabase(let projectRoot): return projectRoot
    case .swiftPM(let projectRoot): return projectRoot
    case .testBuildSystem(let projectRoot): return projectRoot
    }
  }
}

/// Create a build system of the given type.
private func createBuildSystem(
  buildSystemKind: BuildSystemKind,
  options: SourceKitLSPOptions,
  buildSystemTestHooks: BuildSystemTestHooks,
  toolchainRegistry: ToolchainRegistry,
  connectionToSourceKitLSP: any Connection
) async -> BuiltInBuildSystem? {
  switch buildSystemKind {
  case .buildServer(let projectRoot):
    return await BuildServerBuildSystem(projectRoot: projectRoot, connectionToSourceKitLSP: connectionToSourceKitLSP)
  case .compilationDatabase(let projectRoot):
    return CompilationDatabaseBuildSystem(
      projectRoot: projectRoot,
      searchPaths: (options.compilationDatabaseOrDefault.searchPaths ?? []).compactMap {
        try? RelativePath(validating: $0)
      },
      connectionToSourceKitLSP: connectionToSourceKitLSP
    )
  case .swiftPM(let projectRoot):
    return await SwiftPMBuildSystem(
      projectRoot: projectRoot,
      toolchainRegistry: toolchainRegistry,
      options: options,
      connectionToSourceKitLSP: connectionToSourceKitLSP,
      testHooks: buildSystemTestHooks.swiftPMTestHooks
    )
  case .testBuildSystem(let projectRoot):
    return TestBuildSystem(projectRoot: projectRoot, connectionToSourceKitLSP: connectionToSourceKitLSP)
  }
}

/// A type that outwardly acts as a BSP build server and internally uses a `BuiltInBuildSystem` to satisfy the requests.
package actor BuiltInBuildSystemAdapter: QueueBasedMessageHandler {
  package static let signpostLoggingCategory: String = "build-system-message-handling"

  /// The queue on which all messages from SourceKit-LSP (or more specifically `BuildSystemManager`) are handled.
  package let messageHandlingQueue = AsyncQueue<BuildSystemMessageDependencyTracker>()

  /// The underlying build system
  private var underlyingBuildSystem: BuiltInBuildSystem

  /// The connection with which messages are sent to `BuildSystemManager`.
  private let connectionToSourceKitLSP: LocalConnection

  /// If the underlying build system is a `TestBuildSystem`, return it. Otherwise, `nil`
  ///
  /// - Important: For testing purposes only.
  var testBuildSystem: TestBuildSystem? {
    return underlyingBuildSystem as? TestBuildSystem
  }

  /// `messageHandler` is a handler that handles messages sent from the build system to SourceKit-LSP.
  init?(
    buildSystemKind: BuildSystemKind?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    buildSystemTestHooks: BuildSystemTestHooks,
    messagesToSourceKitLSPHandler: MessageHandler
  ) async {
    guard let buildSystemKind else {
      return nil
    }
    self.connectionToSourceKitLSP = LocalConnection(receiverName: "BuildSystemManager")
    connectionToSourceKitLSP.start(handler: messagesToSourceKitLSPHandler)

    let buildSystem = await createBuildSystem(
      buildSystemKind: buildSystemKind,
      options: options,
      buildSystemTestHooks: buildSystemTestHooks,
      toolchainRegistry: toolchainRegistry,
      connectionToSourceKitLSP: connectionToSourceKitLSP
    )
    guard let buildSystem else {
      logger.log("Failed to create build system for \(buildSystemKind.projectRoot.pathString)")
      return nil
    }
    logger.log("Created \(type(of: buildSystem), privacy: .public) for \(buildSystemKind.projectRoot.pathString)")

    self.underlyingBuildSystem = buildSystem
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
        indexDatabasePath: await underlyingBuildSystem.indexDatabasePath?.pathString,
        indexStorePath: await underlyingBuildSystem.indexStorePath?.pathString,
        supportsPreparation: underlyingBuildSystem.supportsPreparation
      ).encodeToLSPAny()
    )
  }

  package func handleImpl(_ notification: some NotificationType) async {
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

  package func handleImpl<Request: RequestType>(_ request: RequestAndReply<Request>) async {
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
