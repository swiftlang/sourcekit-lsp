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
import TSCUtility
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SourceKitLSP
import class Foundation.Pipe
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

  public let client: TestClient
  let connImpl: ConnectionImpl

  public var hasShutdown: Bool = false

  /// The server, if it is in the same process.
  public let server: SourceKitServer?

  public init(connectionKind: ConnectionKind = .local) {

    switch connectionKind {
      case .local:
        let clientConnection = LocalConnection()
        let serverConnection = LocalConnection()
        client = TestClient(server: serverConnection)
        server = SourceKitServer(client: clientConnection, options: Self.serverOptions, onExit: {
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
        server = SourceKitServer(client: serverConnection, options: Self.serverOptions, onExit: {
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
  }

  func close() {
    if !hasShutdown {
      hasShutdown = true
      _ = try! self.client.sendSync(ShutdownRequest())
      self.client.send(ExitNotification())
    }
  }
}
