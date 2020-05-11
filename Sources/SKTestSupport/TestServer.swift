//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
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
import SourceKit
import class Foundation.Pipe
import LSPTestSupport

public struct TestSourceKitServer {
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

        // FIXME: DispatchIO doesn't like when the Pipes close behind its back even after the tests
        // finish. Until we fix the lifetime, leak.
        _ = Unmanaged.passRetained(clientToServer)
        _ = Unmanaged.passRetained(serverToClient)

        let clientConnection = JSONRPCConnection(
          protocol: MessageRegistry.lspProtocol,
          inFD: serverToClient.fileHandleForReading.fileDescriptor,
          outFD: clientToServer.fileHandleForWriting.fileDescriptor
        )
        let serverConnection = JSONRPCConnection(
          protocol: MessageRegistry.lspProtocol,
          inFD: clientToServer.fileHandleForReading.fileDescriptor,
          outFD: serverToClient.fileHandleForWriting.fileDescriptor
        )

        client = TestClient(server: clientConnection)
        server = SourceKitServer(client: serverConnection, options: Self.serverOptions, onExit: {
          serverConnection.close()
        })

        clientConnection.start(receiveHandler: client)
        serverConnection.start(receiveHandler: server!)

        connImpl = .jsonrpc(
          clientToServer: clientToServer,
          serverToClient: serverToClient,
          clientConnection: clientConnection,
          serverConnection: serverConnection)
    }
  }

  func close() {
    switch connImpl {
      case .local(clientConnection: let cc, serverConnection: let sc):
      cc.close()
      sc.close()

    case .jsonrpc(clientToServer: _, serverToClient: _, clientConnection: let cc, serverConnection: let sc):
      cc.close()
      sc.close()
    }
  }
}
