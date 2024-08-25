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

/// A type that outwardly acts as a build server conforming to the Build System Integration Protocol and internally uses
/// a `BuiltInBuildSystem` to satisfy the requests.
package actor BuiltInBuildSystemAdapter: MessageHandler {
  /// The underlying build system
  // FIXME: (BSP Migration) This should be private, all messages should go through BSP. Only accessible from the outside for transition
  // purposes.
  private(set) package var underlyingBuildSystem: BuiltInBuildSystem!
  private let connectionToSourceKitLSP: LocalConnection

  // FIXME: (BSP migration) Can we have more fine-grained dependency tracking here?
  private let messageHandlingQueue = AsyncQueue<Serial>()

  init?(
    buildSystemKind: BuildSystemKind?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    buildSystemTestHooks: BuildSystemTestHooks,
    connectionToSourceKitLSP: LocalConnection
  ) async {
    guard let buildSystemKind else {
      return nil
    }
    self.connectionToSourceKitLSP = connectionToSourceKitLSP

    let buildSystem = await createBuildSystem(
      buildSystemKind: buildSystemKind,
      options: options,
      buildSystemTestHooks: buildSystemTestHooks,
      toolchainRegistry: toolchainRegistry,
      connectionToSourceKitLSP: connectionToSourceKitLSP
    )
    guard let buildSystem else {
      return nil
    }

    self.underlyingBuildSystem = buildSystem
  }

  private func initialize(request: InitializeBuildRequest) async -> InitializeBuildResponse {
    return InitializeBuildResponse(
      displayName: "\(type(of: underlyingBuildSystem))",
      version: "1.0.0",
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

  nonisolated package func handle(_ notification: some NotificationType) {
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: "build-system-message-handling")
      .makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("Notification", id: signpostID, "\(type(of: notification))")
    messageHandlingQueue.async {
      signposter.emitEvent("Start handling", id: signpostID)
      await self.handleImpl(notification)
      signposter.endInterval("Notification", state, "Done")
    }
  }

  private func handleImpl(_ notification: some NotificationType) async {
    switch notification {
    case let notification as DidChangeWatchedFilesNotification:
      await self.underlyingBuildSystem.didChangeWatchedFiles(notification: notification)
    default:
      logger.error("Ignoring unknown notification \(type(of: notification).method) from SourceKit-LSP")
    }
  }

  package nonisolated func handle<R: RequestType>(
    _ params: R,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<R.Response>) -> Void
  ) {
    // FIXME: Can we share this between the different message handler implementations?
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: "build-system-message-handling")
      .makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("Request", id: signpostID, "\(R.self)")

    messageHandlingQueue.async {
      signposter.emitEvent("Start handling", id: signpostID)
      await withTaskCancellationHandler {
        await self.handleImpl(params, id: id, reply: reply)
        signposter.endInterval("Request", state, "Done")
      } onCancel: {
        signposter.emitEvent("Cancelled", id: signpostID)
      }
    }
  }

  private func handleImpl<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) async {
    let startDate = Date()

    let request = RequestAndReply(request) { result in
      reply(result)
      let endDate = Date()
      Task {
        switch result {
        case .success(let response):
          logger.log(
            """
            Succeeded (took \(endDate.timeIntervalSince(startDate) * 1000, privacy: .public)ms)
            \(Request.method, privacy: .public)
            \(response.forLogging)
            """
          )
        case .failure(let error):
          logger.log(
            """
            Failed (took \(endDate.timeIntervalSince(startDate) * 1000, privacy: .public)ms)
            \(Request.method, privacy: .public)(\(id, privacy: .public))
            \(error.forLogging, privacy: .private)
            """
          )
        }
      }
    }

    switch request {
    case let request as RequestAndReply<BuildTargetsRequest>:
      await request.reply { try await underlyingBuildSystem.buildTargets(request: request.params) }
    case let request as RequestAndReply<BuildTargetSourcesRequest>:
      await request.reply { try await underlyingBuildSystem.buildTargetSources(request: request.params) }
    case let request as RequestAndReply<InitializeBuildRequest>:
      await request.reply { await self.initialize(request: request.params) }
    case let request as RequestAndReply<InverseSourcesRequest>:
      await request.reply { try await underlyingBuildSystem.inverseSources(request: request.params) }
    case let request as RequestAndReply<PrepareTargetsRequest>:
      await request.reply { try await underlyingBuildSystem.prepare(request: request.params) }
    case let request as RequestAndReply<SourceKitOptionsRequest>:
      await request.reply { try await underlyingBuildSystem.sourceKitOptions(request: request.params) }
    case let request as RequestAndReply<WaitForBuildSystemUpdatesRequest>:
      await request.reply { await underlyingBuildSystem.waitForUpBuildSystemUpdates(request: request.params) }
    default:
      await request.reply { throw ResponseError.methodNotFound(Request.method) }
    }
  }
}
