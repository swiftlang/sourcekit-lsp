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
import SKSupport

// FIXME: (BSP Migration) This should be a MessageHandler once we have migrated all build system queries to BSP and can use
// LocalConnection for the communication.
protocol BuiltInBuildSystemAdapterDelegate: Sendable {
  func handle(_ notification: some NotificationType) async
  func handle<R: RequestType>(_ request: R) async throws -> R.Response
}

// FIXME: (BSP Migration) This should be a MessageHandler once we have migrated all build system queries to BSP and can use
// LocalConnection for the communication.
package protocol BuiltInBuildSystemMessageHandler: AnyObject, Sendable {
  func sendNotificationToSourceKitLSP(_ notification: some NotificationType) async
  func sendRequestToSourceKitLSP<R: RequestType>(_ request: R) async throws -> R.Response
}

/// A type that outwardly acts as a build server conforming to the Build System Integration Protocol and internally uses
/// a `BuiltInBuildSystem` to satisfy the requests.
actor BuiltInBuildSystemAdapter: BuiltInBuildSystemMessageHandler {
  /// The underlying build system
  // FIXME: (BSP Migration) This should be private, all messages should go through BSP. Only accessible from the outside for transition
  // purposes.
  package let underlyingBuildSystem: BuiltInBuildSystem
  private let messageHandler: any BuiltInBuildSystemAdapterDelegate

  init(
    buildSystem: BuiltInBuildSystem,
    messageHandler: any BuiltInBuildSystemAdapterDelegate
  ) async {
    self.underlyingBuildSystem = buildSystem
    self.messageHandler = messageHandler
    await buildSystem.setMessageHandler(self)
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
    case let request as InverseSourcesRequest:
      return try await handle(request, underlyingBuildSystem.inverseSources)
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

  func sendNotificationToSourceKitLSP(_ notification: some LanguageServerProtocol.NotificationType) async {
    logger.info(
      """
      Received notification from build system
      \(notification.forLogging)
      """
    )
    await messageHandler.handle(notification)
  }

  func sendRequestToSourceKitLSP<R: RequestType>(_ request: R) async throws -> R.Response {
    logger.info(
      """
      Received request from build system
      \(request.forLogging)
      """
    )
    return try await messageHandler.handle(request)
  }

}
