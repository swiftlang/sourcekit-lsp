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
import XCTest

import class Foundation.Pipe

public final class TestJSONRPCConnection {
  public let clientToServer: Pipe = Pipe()
  public let serverToClient: Pipe = Pipe()
  public let client: TestMessageHandler
  public let clientConnection: JSONRPCConnection
  public let server: TestServer
  public let serverConnection: JSONRPCConnection

  public init() {
    clientConnection = JSONRPCConnection(
      name: "client",
      protocol: testMessageRegistry,
      inFD: serverToClient.fileHandleForReading,
      outFD: clientToServer.fileHandleForWriting
    )

    serverConnection = JSONRPCConnection(
      name: "server",
      protocol: testMessageRegistry,
      inFD: clientToServer.fileHandleForReading,
      outFD: serverToClient.fileHandleForWriting
    )

    client = TestMessageHandler(server: clientConnection)
    server = TestServer(client: serverConnection)

    clientConnection.start(receiveHandler: client) {
      // FIXME: keep the pipes alive until we close the connection. This
      // should be fixed systemically.
      withExtendedLifetime(self) {}
    }
    serverConnection.start(receiveHandler: server) {
      // FIXME: keep the pipes alive until we close the connection. This
      // should be fixed systemically.
      withExtendedLifetime(self) {}
    }
  }

  public func close() {
    clientConnection.close()
    serverConnection.close()
  }
}

public struct TestLocalConnection {
  public let client: TestMessageHandler
  public let clientConnection: LocalConnection = .init()
  public let server: TestServer
  public let serverConnection: LocalConnection = .init()

  public init() {
    client = TestMessageHandler(server: serverConnection)
    server = TestServer(client: clientConnection)

    clientConnection.start(handler: client)
    serverConnection.start(handler: server)
  }

  public func close() {
    clientConnection.close()
    serverConnection.close()
  }
}

public final class TestMessageHandler: MessageHandler {
  /// The connection to the language client.
  public let server: Connection

  public init(server: Connection) {
    self.server = server
  }

  var oneShotNotificationHandlers: [((Any) -> Void)] = []

  public var allowUnexpectedNotification: Bool = true

  public func appendOneShotNotificationHandler<N: NotificationType>(_ handler: @escaping (N) -> Void) {
    oneShotNotificationHandlers.append({ anyNote in
      guard let note = anyNote as? N else {
        fatalError("received notification of the wrong type \(anyNote); expected \(N.self)")
      }
      handler(note)
    })
  }

  public func handle(_ notification: some NotificationType, from clientID: ObjectIdentifier) {
    guard !oneShotNotificationHandlers.isEmpty else {
      if allowUnexpectedNotification { return }
      fatalError("unexpected notification \(notification)")
    }
    let handler = oneShotNotificationHandlers.removeFirst()
    handler(notification)
  }

  public func handle<R: RequestType>(
    _ params: R,
    id: RequestID,
    from clientID: ObjectIdentifier,
    reply: @escaping (LSPResult<R.Response>) -> Void
  ) {
    reply(.failure(.methodNotFound(R.method)))
  }
}

extension TestMessageHandler: Connection {

  /// Send a notification to the language server.
  public func send(_ notification: some NotificationType) {
    server.send(notification)
  }

  /// Send a request to the language server and (asynchronously) receive a reply.
  public func send<Request: RequestType>(
    _ request: Request,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    return server.send(request, reply: reply)
  }
}

public final class TestServer: MessageHandler {
  public let client: Connection

  init(client: Connection) {
    self.client = client
  }

  public func handle(_ params: some NotificationType, from clientID: ObjectIdentifier) {
    if params is EchoNotification {
      self.client.send(params)
    } else {
      fatalError("Unhandled notification")
    }
  }

  public func handle<R: RequestType>(
    _ params: R,
    id: RequestID,
    from clientID: ObjectIdentifier,
    reply: @escaping (LSPResult<R.Response>) -> Void
  ) {
    if let params = params as? EchoRequest {
      reply(.success(params.string as! R.Response))
    } else if let params = params as? EchoError {
      if let code = params.code {
        reply(.failure(ResponseError(code: code, message: params.message!)))
      } else {
        reply(.success(VoidResponse() as! R.Response))
      }
    } else {
      fatalError("Unhandled request")
    }
  }
}

// MARK: Test requests.

private let testMessageRegistry = MessageRegistry(
  requests: [EchoRequest.self, EchoError.self],
  notifications: [EchoNotification.self]
)

#if swift(<5.10)
extension String: ResponseType {}
#else
extension String: @retroactive ResponseType {}
#endif

public struct EchoRequest: RequestType {
  public static var method: String = "test_server/echo"
  public typealias Response = String

  public var string: String

  public init(string: String) {
    self.string = string
  }
}

public struct EchoError: RequestType {
  public static var method: String = "test_server/echo_error"
  public typealias Response = VoidResponse

  public var code: ErrorCode?
  public var message: String?

  public init(code: ErrorCode? = nil, message: String? = nil) {
    self.code = code
    self.message = message
  }
}

public struct EchoNotification: NotificationType {
  public static var method: String = "test_server/echo_note"

  public var string: String

  public init(string: String) {
    self.string = string
  }
}
