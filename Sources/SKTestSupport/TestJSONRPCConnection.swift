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

import InProcessClient
@_spi(SourceKitLSP) public import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) package import LanguageServerProtocolTransport
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

package import class Foundation.Pipe

package final class TestJSONRPCConnection: Sendable {
  package let clientToServer: Pipe = Pipe()
  package let serverToClient: Pipe = Pipe()

  /// Mocks a client (aka. editor) that can send requests to the LSP server.
  package let client: TestClient

  /// The connection with which the client can send requests and notifications to the LSP server and using which it
  /// receives replies to the requests.
  package let clientToServerConnection: JSONRPCConnection

  /// Mocks an LSP server that handles requests from the client.
  package let server: TestServer

  /// The connection with which the server can send requests and notifications to the client and using which it
  /// receives replies to the requests.
  package let serverToClientConnection: JSONRPCConnection

  package init(allowUnexpectedNotification: Bool = true) {
    clientToServerConnection = JSONRPCConnection(
      name: "client",
      protocol: testMessageRegistry,
      inFD: serverToClient.fileHandleForReading,
      outFD: clientToServer.fileHandleForWriting
    )

    serverToClientConnection = JSONRPCConnection(
      name: "server",
      protocol: testMessageRegistry,
      inFD: clientToServer.fileHandleForReading,
      outFD: serverToClient.fileHandleForWriting
    )

    client = TestClient(
      connectionToServer: clientToServerConnection,
      allowUnexpectedNotification: allowUnexpectedNotification
    )
    server = TestServer(client: serverToClientConnection)

    clientToServerConnection.start(receiveHandler: client) {
      // Keep the pipes alive until we close the connection.
      withExtendedLifetime(self) {}
    }
    serverToClientConnection.start(receiveHandler: server) {
      // Keep the pipes alive until we close the connection.
      withExtendedLifetime(self) {}
    }
  }

  package func close() {
    clientToServerConnection.close()
    serverToClientConnection.close()
  }
}

package struct TestLocalConnection {
  package let client: TestClient
  package let clientConnection: LocalConnection = LocalConnection(receiverName: "Test")
  package let server: TestServer
  package let serverConnection: LocalConnection = LocalConnection(receiverName: "Test")

  package init(allowUnexpectedNotification: Bool = true) {
    client = TestClient(connectionToServer: serverConnection, allowUnexpectedNotification: allowUnexpectedNotification)
    server = TestServer(client: clientConnection)

    clientConnection.start(handler: client)
    serverConnection.start(handler: server)
  }

  package func close() {
    clientConnection.close()
    serverConnection.close()
  }
}

package actor TestClient: MessageHandler {
  /// The connection to the LSP server.
  package let connectionToServer: any Connection

  private let messageHandlingQueue = AsyncQueue<Serial>()

  private var oneShotNotificationHandlers: [((Any) -> Void)] = []

  private let allowUnexpectedNotification: Bool

  package init(connectionToServer: any Connection, allowUnexpectedNotification: Bool = true) {
    self.connectionToServer = connectionToServer
    self.allowUnexpectedNotification = allowUnexpectedNotification
  }

  package func appendOneShotNotificationHandler<N: NotificationType>(_ handler: @escaping (N) -> Void) {
    oneShotNotificationHandlers.append({ anyNotification in
      guard let notification = anyNotification as? N else {
        fatalError("received notification of the wrong type \(anyNotification); expected \(N.self)")
      }
      handler(notification)
    })
  }

  /// The LSP server sent a notification to the client. Handle it.
  package nonisolated func handle(_ notification: some NotificationType) {
    messageHandlingQueue.async {
      await self.handleNotificationImpl(notification)
    }
  }

  package func handleNotificationImpl(_ notification: some NotificationType) {
    guard !oneShotNotificationHandlers.isEmpty else {
      if allowUnexpectedNotification { return }
      fatalError("unexpected notification \(notification)")
    }
    let handler = oneShotNotificationHandlers.removeFirst()
    handler(notification)
  }

  /// The LSP server sent a request to the client. Handle it.
  package nonisolated func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) {
    reply(.failure(.methodNotFound(Request.method)))
  }

  /// Send a notification to the LSP server.
  package nonisolated func send(_ notification: some NotificationType) {
    connectionToServer.send(notification)
  }

  /// Send a request to the LSP server and (asynchronously) receive a reply.
  package nonisolated func send<Request: RequestType>(
    _ request: Request,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    return connectionToServer.send(request, reply: reply)
  }
}

package final class TestServer: MessageHandler {
  package let client: any Connection

  init(client: any Connection) {
    self.client = client
  }

  /// The client sent a notification to the server. Handle it.
  package func handle(_ notification: some NotificationType) {
    if notification is EchoNotification {
      self.client.send(notification)
    } else {
      fatalError("Unhandled notification")
    }
  }

  /// The client sent a request to the server. Handle it.
  package func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) {
    if let params = request as? EchoRequest {
      reply(.success(params.string as! Request.Response))
    } else if let params = request as? EchoError {
      if let code = params.code {
        reply(.failure(ResponseError(code: code, message: params.message!)))
      } else {
        reply(.success(VoidResponse() as! Request.Response))
      }
    } else {
      fatalError("Unhandled request")
    }
  }
}

// MARK: Test requests

private let testMessageRegistry = MessageRegistry(
  requests: [EchoRequest.self, EchoError.self],
  notifications: [EchoNotification.self, ShowMessageNotification.self]
)

extension String: LanguageServerProtocol.ResponseType {}

package struct EchoRequest: RequestType {
  package static let method: String = "test_server/echo"
  package typealias Response = String

  package var string: String

  package init(string: String) {
    self.string = string
  }
}

package struct EchoError: RequestType {
  package static let method: String = "test_server/echo_error"
  package typealias Response = VoidResponse

  package var code: ErrorCode?
  package var message: String?

  package init(code: ErrorCode? = nil, message: String? = nil) {
    self.code = code
    self.message = message
  }
}

package struct EchoNotification: NotificationType {
  package static let method: String = "test_server/echo_note"

  package var string: String

  package init(string: String) {
    self.string = string
  }
}
