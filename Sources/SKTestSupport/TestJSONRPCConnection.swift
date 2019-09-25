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
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import class Foundation.Pipe
import XCTest

// Workaround ambiguity with Foundation.
public typealias Notification = LanguageServerProtocol.Notification

public struct TestJSONRPCConnection {
  public let clientToServer: Pipe = Pipe()
  public let serverToClient: Pipe = Pipe()
  public let client: TestClient
  public let clientConnection: JSONRPCConection
  public let server: TestServer
  public let serverConnection: JSONRPCConection

  public init() {
    // FIXME: DispatchIO doesn't like when the Pipes close behind its back even after the tests
    // finish. Until we fix the lifetime, leak.
    _ = Unmanaged.passRetained(clientToServer)
    _ = Unmanaged.passRetained(serverToClient)

    clientConnection = JSONRPCConection(
      protocol: testMessageRegistry,
      inFD: serverToClient.fileHandleForReading.fileDescriptor,
      outFD: clientToServer.fileHandleForWriting.fileDescriptor
    )

    serverConnection = JSONRPCConection(
      protocol: testMessageRegistry,
      inFD: clientToServer.fileHandleForReading.fileDescriptor,
      outFD: serverToClient.fileHandleForWriting.fileDescriptor
    )

    client = TestClient(server: clientConnection)
    server = TestServer(client: serverConnection)

    clientConnection.start(receiveHandler: client)
    serverConnection.start(receiveHandler: server)
  }

  public func close() {
    clientConnection.close()
    serverConnection.close()
  }
}

public struct TestLocalConnection {
  public let client: TestClient
  public let clientConnection: LocalConnection = .init()
  public let server: TestServer
  public let serverConnection: LocalConnection = .init()

  public init() {
    client = TestClient(server: serverConnection)
    server = TestServer(client: clientConnection)

    clientConnection.start(handler: client)
    serverConnection.start(handler: server)
  }

  public func close() {
    clientConnection.close()
    serverConnection.close()
  }
}

public final class TestClient: LanguageServerEndpoint {

  /// The connection to the language client.
  public let server: Connection

  public init(server: Connection) {
    self.server = server
    super.init()
  }

  public var replyQueue: DispatchQueue = DispatchQueue(label: "testclient-reply-queue")
  var oneShotNotificationHandlers: [((Any) -> Void)] = []

  public var allowUnexpectedNotification: Bool = true
  public var allowUnexpectedRequest: Bool = false

  public func appendOneShotNotificationHandler<N>(_ handler: @escaping (Notification<N>) -> Void) {
    oneShotNotificationHandlers.append({ anyNote in
      guard let note = anyNote as? Notification<N> else {
        fatalError("received notification of the wrong type \(anyNote); expected \(N.self)")
      }
      handler(note)
    })
  }

  public func handleNextNotification<N>(_ handler: @escaping (Notification<N>) -> Void) {
    precondition(oneShotNotificationHandlers.isEmpty)
    appendOneShotNotificationHandler(handler)
  }

  override public func _registerBuiltinHandlers() {

  }

  override public func _handleUnknown<N>(_ notification: Notification<N>) {
    guard !oneShotNotificationHandlers.isEmpty else {
      if allowUnexpectedNotification { return }
      fatalError("unexpected notification \(notification)")
    }
    let handler = oneShotNotificationHandlers.removeFirst()
    handler(notification)
  }

  override public func _handleUnknown<R>(_ request: Request<R>) where R : RequestType {
    guard allowUnexpectedRequest else {
      fatalError("unexpected request \(request)")
    }
    request.reply(.failure(.cancelled))
  }
}

extension TestClient: Connection {

  /// Send a notification to the language server.
  public func send<Notification>(_ notification: Notification) where Notification: NotificationType {
    server.send(notification)
  }

  /// Send a request to the language server and (asynchronously) receive a reply.
  public func send<Request>(_ request: Request, queue: DispatchQueue, reply: @escaping (LSPResult<Request.Response>) -> Void) -> RequestID where Request: RequestType {
    return server.send(request, queue: queue, reply: reply)
  }

  /// Convenience method to get reply on replyQueue.
  public func send<Request>(_ request: Request, reply: @escaping (LSPResult<Request.Response>) -> Void) -> RequestID where Request: RequestType {
    return send(request, queue: replyQueue, reply: reply)
  }


  /// Send a notification and expect a notification in reply synchronously.
  /// For testing notifications that behave like requests  - e.g. didChange & publishDiagnostics.
  public func sendNoteSync<NSend, NReply>(_ notification: NSend, _ handler: @escaping (Notification<NReply>) -> Void) where NSend: NotificationType {

    let expectation = XCTestExpectation(description: "sendNoteSync - note received")

    handleNextNotification { (note: Notification<NReply>) in
      handler(note)
      expectation.fulfill()
    }

    send(notification)

    let result = XCTWaiter.wait(for: [expectation], timeout: 15)
    if result != .completed {
      fatalError("error \(result) waiting for notification in response to \(notification)")
    }
  }

  /// Send a notification and expect two notifications in reply synchronously.
  /// For testing notifications that behave like requests  - e.g. didChange & publishDiagnostics.
  public func sendNoteSync<NSend, NReply1, NReply2>(
    _ notification: NSend,
    _ handler1: @escaping (Notification<NReply1>) -> Void,
    _ handler2: @escaping (Notification<NReply2>) -> Void
  ) where NSend: NotificationType {

    let expectation = XCTestExpectation(description: "sendNoteSync - note received")
    expectation.expectedFulfillmentCount = 2

    handleNextNotification { (note: Notification<NReply1>) in
      handler1(note)
      expectation.fulfill()
    }
    appendOneShotNotificationHandler { (note: Notification<NReply2>) in
      handler2(note)
      expectation.fulfill()
    }

    send(notification)

    let result = XCTWaiter.wait(for: [expectation], timeout: 15)
    if result != .completed {
      fatalError("error \(result) waiting for notification in response to \(notification)")
    }
  }
}

public final class TestServer: LanguageServer {

  override public func _registerBuiltinHandlers() {
    register { (req: Request<EchoRequest>) in
      req.reply(req.params.string)
    }

    register { (req: Request<EchoError>) in
      if let code = req.params.code {
        req.reply(.failure(ResponseError(code: code, message: req.params.message!)))
      } else {
        req.reply(VoidResponse())
      }
    }

    register { [unowned self] (note:  Notification<EchoNotification>) in
      self.client.send(note.params)
    }
  }

  override public func _handleUnknown<R>(_ request: Request<R>) {
    fatalError()
  }

  override public func _handleUnknown<N>(_ notification:  Notification<N>) {
    fatalError()
  }
}

// MARK: Test requests.

private let testMessageRegistry = MessageRegistry(
  requests: [EchoRequest.self, EchoError.self],
  notifications: [EchoNotification.self])

extension String: ResponseType {}

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
