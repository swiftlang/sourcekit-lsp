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

import SKSupport
import SKCore
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SourceKitLSP
import Foundation
import LSPTestSupport

public final class TestSourceKitServer {
  public enum ConnectionKind {
    case local, jsonrpc
  }

  enum ConnectionImpl {
    case local(
      clientConnection: LocalConnection,
      serverConnection: LocalConnection)
    case jsonrpc(
      clientToServer: Pipe,
      serverToClient: Pipe,
      clientConnection: JSONRPCConnection,
      serverConnection: JSONRPCConnection)
  }

  public static let serverOptions: SourceKitServer.Options = SourceKitServer.Options()

  /// If the server is not using the global module cache, the path of the local
  /// module cache.
  ///
  /// This module cache will be deleted when the test server is destroyed.
  private let moduleCache: URL?

  public let client: TestClient
  let connImpl: ConnectionImpl

  public var hasShutdown: Bool = false

  /// The server, if it is in the same process.
  public let server: SourceKitServer?
  
  /// - Parameters:
  ///   - useGlobalModuleCache: If `false`, the server will use its own module
  ///     cache in an empty temporary directory instead of the global module cache.
  public init(connectionKind: ConnectionKind = .local, useGlobalModuleCache: Bool = true) {
    if !useGlobalModuleCache {
      moduleCache = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    } else {
      moduleCache = nil
    }
    var serverOptions = Self.serverOptions
    if let moduleCache {
      serverOptions.buildSetup.flags.swiftCompilerFlags += ["-module-cache-path", moduleCache.path]
    }

    switch connectionKind {
      case .local:
        let clientConnection = LocalConnection()
        let serverConnection = LocalConnection()
        client = TestClient(server: serverConnection)
        server = SourceKitServer(client: clientConnection, options: serverOptions, onExit: {
          clientConnection.close()
        })

        clientConnection.start(handler: client)
        serverConnection.start(handler: server!)

        connImpl = .local(clientConnection: clientConnection, serverConnection: serverConnection)

      case .jsonrpc:
        let clientToServer: Pipe = Pipe()
        let serverToClient: Pipe = Pipe()

        let clientConnection = JSONRPCConnection(
          protocol: MessageRegistry.lspProtocol,
          inFD: serverToClient.fileHandleForReading,
          outFD: clientToServer.fileHandleForWriting
        )
        let serverConnection = JSONRPCConnection(
          protocol: MessageRegistry.lspProtocol,
          inFD: clientToServer.fileHandleForReading,
          outFD: serverToClient.fileHandleForWriting
        )

        client = TestClient(server: clientConnection)
        server = SourceKitServer(client: serverConnection, options: serverOptions, onExit: {
          serverConnection.close()
        })

        clientConnection.start(receiveHandler: client) {
          // FIXME: keep the pipes alive until we close the connection. This
          // should be fixed systemically.
          withExtendedLifetime((clientToServer, serverToClient)) {}
        }
        serverConnection.start(receiveHandler: server!) {
          // FIXME: keep the pipes alive until we close the connection. This
          // should be fixed systemically.
          withExtendedLifetime((clientToServer, serverToClient)) {}
        }

        connImpl = .jsonrpc(
          clientToServer: clientToServer,
          serverToClient: serverToClient,
          clientConnection: clientConnection,
          serverConnection: serverConnection)
    }
  }

  deinit {
    close()

    if let moduleCache {
      try? FileManager.default.removeItem(at: moduleCache)
    }
  }

  func close() {
    if !hasShutdown {
      hasShutdown = true
      _ = try! self.client.sendSync(ShutdownRequest())
      self.client.send(ExitNotification())
    }
  }
}
