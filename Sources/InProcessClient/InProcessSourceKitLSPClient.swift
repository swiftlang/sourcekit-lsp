//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
public import Foundation
@_spi(SourceKitLSP) public import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
public import SKOptions
package import SourceKitLSP
import SwiftExtensions
import TSCExtensions
package import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

import struct TSCBasic.AbsolutePath

/// Launches a `SourceKitLSPServer` in-process and allows sending messages to it.
public final class InProcessSourceKitLSPClient: Sendable {
  private let server: SourceKitLSPServer

  private let nextRequestID = AtomicUInt32(initialValue: 0)

  public convenience init(
    toolchainPath: URL?,
    options: SourceKitLSPOptions = SourceKitLSPOptions(),
    capabilities: ClientCapabilities = ClientCapabilities(),
    workspaceFolders: [WorkspaceFolder],
    messageHandler: any MessageHandler
  ) async throws {
    try await self.init(
      toolchainRegistry: ToolchainRegistry(installPath: toolchainPath),
      options: options,
      capabilities: capabilities,
      workspaceFolders: workspaceFolders,
      messageHandler: messageHandler
    )
  }

  /// Create a new `SourceKitLSPServer`. An `InitializeRequest` is automatically sent to the server.
  ///
  /// `messageHandler` handles notifications and requests sent from the SourceKit-LSP server to the client.
  package init(
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions = SourceKitLSPOptions(),
    hooks: Hooks = Hooks(),
    capabilities: ClientCapabilities = ClientCapabilities(),
    workspaceFolders: [WorkspaceFolder],
    messageHandler: any MessageHandler
  ) async throws {
    LoggingScope.configureDefaultLoggingSubsystem("org.swift.sourcekit-lsp")
    let serverToClientConnection = LocalConnection(receiverName: "client")
    self.server = SourceKitLSPServer(
      client: serverToClientConnection,
      toolchainRegistry: toolchainRegistry,
      languageServerRegistry: .staticallyKnownServices,
      options: options,
      hooks: hooks,
      onExit: {
        serverToClientConnection.close()
      }
    )
    serverToClientConnection.start(handler: messageHandler)
    _ = try await self.send(
      InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
        initializationOptions: nil,
        capabilities: capabilities,
        trace: .off,
        workspaceFolders: workspaceFolders
      )
    )
  }

  /// Send the request to `server` and return the request result.
  ///
  /// - Important: Because this is an async function, Swift concurrency makes no guarantees about the execution ordering
  ///   of this request with regard to other requests to the server. If execution of requests in a particular order is
  ///   necessary and the response of the request is not awaited, use the version of the function that takes a
  ///   completion handler
  public func send<R: RequestType>(_ request: R) async throws -> R.Response {
    let requestId = ThreadSafeBox<RequestID?>(initialValue: nil)
    return try await withTaskCancellationHandler {
      return try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          // Check if the task has been cancelled before we send the request to LSP to avoid any kind of work if
          // possible.
          return continuation.resume(throwing: CancellationError())
        }
        requestId.value = self.send(request) {
          continuation.resume(with: $0)
        }
        if Task.isCancelled, let requestId = requestId.takeValue() {
          // The task might have been cancelled after the above cancellation check but before `requestId` was assigned
          // a value. To cover that case, check for cancellation here again. Note that we won't cancel twice from here
          // and the `onCancel` handler because we take the request ID out of the `ThreadSafeBox` before sending the
          // `CancelRequestNotification`.
          self.send(CancelRequestNotification(id: requestId))
        }
      }
    } onCancel: {
      if let requestId = requestId.takeValue() {
        self.send(CancelRequestNotification(id: requestId))
      }
    }
  }

  /// Send the request to `server` and return the request result via a completion handler.
  @discardableResult
  public func send<R: RequestType>(
    _ request: R,
    reply: @Sendable @escaping (LSPResult<R.Response>) -> Void
  ) -> RequestID {
    let requestID = RequestID.string("sk-\(Int(nextRequestID.fetchAndIncrement()))")
    server.handle(request, id: requestID, reply: reply)
    return requestID
  }

  /// Send the request to `server` and return the request result via a completion handler.
  ///
  /// The request ID must not start with `sk-` to avoid conflicting with the request IDs that are created by
  /// `send(:reply:)`.
  public func send<R: RequestType>(
    _ request: R,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<R.Response>) -> Void
  ) {
    if case .string(let string) = id {
      if string.starts(with: "sk-") {
        logger.fault("Manually specified request ID must not have reserved prefix 'sk-'")
      }
    }
    server.handle(request, id: id, reply: reply)
  }

  /// Send the notification to `server`.
  public func send(_ notification: some NotificationType) {
    server.handle(notification)
  }
}
