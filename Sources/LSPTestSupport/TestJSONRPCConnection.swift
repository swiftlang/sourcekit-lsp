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

import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKSupport
import XCTest

import class Foundation.Pipe

public final class TestJSONRPCConnection {
  public let clientToServer: Pipe = Pipe()
  public let serverToClient: Pipe = Pipe()

  /// Mocks a client (aka. editor) that can send requests to the LSP server.
  public let client: TestClient

  /// The connection with which the client can send requests and notifications to the LSP server and using which it
  /// receives replies to the requests.
  public let clientToServerConnection: JSONRPCConnection

  /// Mocks an LSP server that handles requests from the client.
  public let server: TestServer

  /// The connection with which the server can send requests and notifications to the client and using which it
  /// receives replies to the requests.
  public let serverToClientConnection: JSONRPCConnection

  public init(allowUnexpectedNotification: Bool = true) {
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
      // FIXME: keep the pipes alive until we close the connection. This
      // should be fixed systemically.
      withExtendedLifetime(self) {}
    }
    serverToClientConnection.start(receiveHandler: server) {
      // FIXME: keep the pipes alive until we close the connection. This
      // should be fixed systemically.
      withExtendedLifetime(self) {}
    }
  }

  public func close() {
    clientToServerConnection.close()
    serverToClientConnection.close()
  }
}

public struct TestLocalConnection {
  public let client: TestClient
  public let clientConnection: LocalConnection = LocalConnection()
  public let server: TestServer
  public let serverConnection: LocalConnection = LocalConnection()

  public init(allowUnexpectedNotification: Bool = true) {
    client = TestClient(connectionToServer: serverConnection, allowUnexpectedNotification: allowUnexpectedNotification)
    server = TestServer(client: clientConnection)

    clientConnection.start(handler: client)
    serverConnection.start(handler: server)
  }

  public func close() {
    clientConnection.close()
    serverConnection.close()
  }
}

public actor TestClient: MessageHandler {
  /// The connection to the LSP server.
  public let connectionToServer: Connection

  private let messageHandlingQueue = AsyncQueue<Serial>()

  private var oneShotNotificationHandlers: [((Any) -> Void)] = []

  private let allowUnexpectedNotification: Bool

  public init(connectionToServer: Connection, allowUnexpectedNotification: Bool = true) {
    self.connectionToServer = connectionToServer
    self.allowUnexpectedNotification = allowUnexpectedNotification
  }

  public func appendOneShotNotificationHandler<N: NotificationType>(_ handler: @escaping (N) -> Void) {
    oneShotNotificationHandlers.append({ anyNote in
      guard let note = anyNote as? N else {
        fatalError("received notification of the wrong type \(anyNote); expected \(N.self)")
      }
      handler(note)
    })
  }

  /// The LSP server sent a notification to the client. Handle it.
  public nonisolated func handle(_ notification: some NotificationType) {
    messageHandlingQueue.async {
      await self.handleNotificationImpl(notification)
    }
  }

  public func handleNotificationImpl(_ notification: some NotificationType) {
    guard !oneShotNotificationHandlers.isEmpty else {
      if allowUnexpectedNotification { return }
      fatalError("unexpected notification \(notification)")
    }
    let handler = oneShotNotificationHandlers.removeFirst()
    handler(notification)
  }

  /// The LSP server sent a request to the client. Handle it.
  public nonisolated func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) {
    reply(.failure(.methodNotFound(Request.method)))
  }

  /// Send a notification to the LSP server.
  public nonisolated func send(_ notification: some NotificationType) {
    connectionToServer.send(notification)
  }

  /// Send a request to the LSP server and (asynchronously) receive a reply.
  public nonisolated func send<Request: RequestType>(
    _ request: Request,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    return connectionToServer.send(request, reply: reply)
  }
}

public final class TestServer: MessageHandler {
  public let client: Connection

  init(client: Connection) {
    self.client = client
  }

  /// The client sent a notification to the server. Handle it.
  public func handle(_ notification: some NotificationType) {
    if notification is EchoNotification {
      self.client.send(notification)
    } else {
      fatalError("Unhandled notification")
    }
  }

  /// The client sent a request to the server. Handle it.
  public func handle<Request: RequestType>(
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

#if compiler(<5.11)
extension String: ResponseType {}
#else
extension String: @retroactive ResponseType {}
#endif

public struct EchoRequest: RequestType {
  public static let method: String = "test_server/echo"
  public typealias Response = String

  public var string: String

  public init(string: String) {
    self.string = string
  }
}

public struct EchoError: RequestType {
  public static let method: String = "test_server/echo_error"
  public typealias Response = VoidResponse

  public var code: ErrorCode?
  public var message: String?

  public init(code: ErrorCode? = nil, message: String? = nil) {
    self.code = code
    self.message = message
  }
}

public struct EchoNotification: NotificationType {
  public static let method: String = "test_server/echo_note"

  public var string: String

  public init(string: String) {
    self.string = string
  }
}
