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

import BuildSystemIntegration
public import Foundation
public import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SwiftExtensions
import Synchronization
import TSCExtensions

import struct TSCBasic.AbsolutePath

#if compiler(>=6)
package import SKOptions
package import SourceKitLSP
package import ToolchainRegistry
#else
import SKOptions
import SourceKitLSP
import ToolchainRegistry
#endif

/// Launches a `SourceKitLSPServer` in-process and allows sending messages to it.
public final class InProcessSourceKitLSPClient: Sendable {
  private let server: SourceKitLSPServer

  private let nextRequestID: Atomic<Int> = Atomic(0)

  public convenience init(
    toolchainPath: URL?,
    capabilities: ClientCapabilities = ClientCapabilities(),
    workspaceFolders: [WorkspaceFolder],
    messageHandler: any MessageHandler
  ) async throws {
    try await self.init(
      toolchainRegistry: ToolchainRegistry(installPath: toolchainPath),
      options: SourceKitLSPOptions(),
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
    let serverToClientConnection = LocalConnection(receiverName: "client")
    self.server = SourceKitLSPServer(
      client: serverToClientConnection,
      toolchainRegistry: toolchainRegistry,
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
    return try await withCheckedThrowingContinuation { continuation in
      self.send(request) {
        continuation.resume(with: $0)
      }
    }
  }

  /// Send the request to `server` and return the request result via a completion handler.
  public func send<R: RequestType>(_ request: R, reply: @Sendable @escaping (LSPResult<R.Response>) -> Void) {
    server.handle(
      request,
      id: .number(Int(nextRequestID.add(1, ordering: .sequentiallyConsistent).oldValue)),
      reply: reply
    )
  }

  /// Send the notification to `server`.
  public func send(_ notification: some NotificationType) {
    server.handle(notification)
  }
}
