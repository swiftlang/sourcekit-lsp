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
import SKLogging
import SKOptions
import SKSupport
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

// FIXME: (BSP Migration) This should be a MessageHandler once we have migrated all build system queries to BSP and can use
// LocalConnection for the communication.
protocol BuiltInBuildSystemAdapterDelegate: Sendable, AnyObject {
  func handle(_ notification: some NotificationType) async
  func handle<R: RequestType>(_ request: R) async throws -> R.Response
}

// FIXME: (BSP Migration) This should be a MessageHandler once we have migrated all build system queries to BSP and can use
// LocalConnection for the communication.
package protocol BuiltInBuildSystemMessageHandler: AnyObject, Sendable {
  func sendNotificationToSourceKitLSP(_ notification: some NotificationType) async
  func sendRequestToSourceKitLSP<R: RequestType>(_ request: R) async throws -> R.Response
}

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
  swiftpmTestHooks: SwiftPMTestHooks,
  toolchainRegistry: ToolchainRegistry,
  messageHandler: BuiltInBuildSystemMessageHandler,
  reloadPackageStatusCallback: @Sendable @escaping (ReloadPackageStatus) async -> Void
) async -> BuiltInBuildSystem? {
  switch buildSystemKind {
  case .buildServer(let projectRoot):
    return await BuildServerBuildSystem(projectRoot: projectRoot, messageHandler: messageHandler)
  case .compilationDatabase(let projectRoot):
    return CompilationDatabaseBuildSystem(
      projectRoot: projectRoot,
      searchPaths: (options.compilationDatabaseOrDefault.searchPaths ?? []).compactMap {
        try? RelativePath(validating: $0)
      },
      messageHandler: messageHandler
    )
  case .swiftPM(let projectRoot):
    return await SwiftPMBuildSystem(
      projectRoot: projectRoot,
      toolchainRegistry: toolchainRegistry,
      options: options,
      messageHandler: messageHandler,
      reloadPackageStatusCallback: reloadPackageStatusCallback,
      testHooks: swiftpmTestHooks
    )
  case .testBuildSystem(let projectRoot):
    return TestBuildSystem(projectRoot: projectRoot, messageHandler: messageHandler)
  }
}

/// A type that outwardly acts as a build server conforming to the Build System Integration Protocol and internally uses
/// a `BuiltInBuildSystem` to satisfy the requests.
package actor BuiltInBuildSystemAdapter: BuiltInBuildSystemMessageHandler {
  /// The underlying build system
  // FIXME: (BSP Migration) This should be private, all messages should go through BSP. Only accessible from the outside for transition
  // purposes.
  private(set) package var underlyingBuildSystem: BuiltInBuildSystem!
  private weak var messageHandler: (any BuiltInBuildSystemAdapterDelegate)?

  init?(
    buildSystemKind: BuildSystemKind?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    swiftpmTestHooks: SwiftPMTestHooks,
    reloadPackageStatusCallback: @Sendable @escaping (ReloadPackageStatus) async -> Void,
    messageHandler: any BuiltInBuildSystemAdapterDelegate
  ) async {
    guard let buildSystemKind else {
      return nil
    }
    self.messageHandler = messageHandler

    let buildSystem = await createBuildSystem(
      buildSystemKind: buildSystemKind,
      options: options,
      swiftpmTestHooks: swiftpmTestHooks,
      toolchainRegistry: toolchainRegistry,
      messageHandler: self,
      reloadPackageStatusCallback: reloadPackageStatusCallback
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

  package func send<R: RequestType>(_ request: R) async throws -> R.Response {
    logger.info(
      """
      Received request to build system
      \(request.forLogging)
      """
    )
    /// Executes `body` and casts the result type to `R.Response`, statically checking that the return type of `body` is
    /// the response type of `request`.
    func handle<HandledRequestType: RequestType>(
      _ request: HandledRequestType,
      _ body: (HandledRequestType) async throws -> HandledRequestType.Response
    ) async throws -> R.Response {
      return try await body(request) as! R.Response
    }

    switch request {
    case let request as BuildTargetsRequest:
      return try await handle(request, underlyingBuildSystem.buildTargets)
    case let request as BuildTargetSourcesRequest:
      return try await handle(request, underlyingBuildSystem.buildTargetSources)
    case let request as InitializeBuildRequest:
      return try await handle(request, self.initialize)
    case let request as InverseSourcesRequest:
      return try await handle(request, underlyingBuildSystem.inverseSources)
    case let request as PrepareTargetsRequest:
      return try await handle(request, underlyingBuildSystem.prepare)
    case let request as SourceKitOptionsRequest:
      return try await handle(request, underlyingBuildSystem.sourceKitOptions)
    case let request as WaitForBuildSystemUpdatesRequest:
      return try await handle(request, underlyingBuildSystem.waitForUpBuildSystemUpdates)
    default:
      throw ResponseError.methodNotFound(R.method)
    }
  }

  package func send(_ notification: some NotificationType) async {
    logger.info(
      """
      Sending notification to build system
      \(notification.forLogging)
      """
    )
    // FIXME: (BSP Migration) These messages should be handled using a LocalConnection, which also gives us logging for the messages
    // sent. We can only do this once all requests to the build system have been migrated and we can implement proper
    // dependency management between the BSP messages
    switch notification {
    case let notification as DidChangeWatchedFilesNotification:
      await self.underlyingBuildSystem.didChangeWatchedFiles(notification: notification)
    default:
      logger.error("Ignoring unknown notification \(type(of: notification).method) from SourceKit-LSP")
    }
  }

  package func sendNotificationToSourceKitLSP(_ notification: some LanguageServerProtocol.NotificationType) async {
    logger.info(
      """
      Received notification from build system
      \(notification.forLogging)
      """
    )
    guard let messageHandler else {
      logger.error("Ignoring notificaiton \(notification.forLogging) because message handler has been deallocated")
      return
    }
    await messageHandler.handle(notification)
  }

  package func sendRequestToSourceKitLSP<R: RequestType>(_ request: R) async throws -> R.Response {
    logger.info(
      """
      Received request from build system
      \(request.forLogging)
      """
    )
    guard let messageHandler else {
      throw ResponseError.unknown("Connection to SourceKit-LSP closed")
    }
    return try await messageHandler.handle(request)
  }

}
