//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKSupport
import SKCore
import SPMUtility
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SourceKit
import class Foundation.Pipe

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
      clientConnection: JSONRPCConection,
      serverConnection: JSONRPCConection)
  }

  public static let buildSetup: BuildSetup = BuildSetup(configuration: .debug,
                                                        path: nil,
                                                        flags: BuildFlags())

  public let client: TestClient
  let connImpl: ConnectionImpl

  /// The server, if it is in the same process.
  public let server: SourceKitServer?

  public init(connectionKind: ConnectionKind = .local) {
     _ = initRequestsOnce

    switch connectionKind {
      case .local:
        let clientConnection = LocalConnection()
        let serverConnection = LocalConnection()
        client = TestClient(server: serverConnection)
        server = SourceKitServer(client: clientConnection, buildSetup: TestSourceKitServer.buildSetup, onExit: {
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

        let clientConnection = JSONRPCConection(
          inFD: serverToClient.fileHandleForReading.fileDescriptor,
          outFD: clientToServer.fileHandleForWriting.fileDescriptor
        )
        let serverConnection = JSONRPCConection(
          inFD: clientToServer.fileHandleForReading.fileDescriptor,
          outFD: serverToClient.fileHandleForWriting.fileDescriptor
        )

        client = TestClient(server: clientConnection)
        server = SourceKitServer(client: serverConnection, buildSetup: TestSourceKitServer.buildSetup, onExit: {
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
