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
@_spi(Testing) import LanguageServerProtocolJSONRPC
import SKTestSupport
import XCTest

import class Foundation.Pipe

#if os(Windows)
import WinSDK
#endif

class ConnectionTests: XCTestCase {

  var connection: TestJSONRPCConnection! = nil

  override func setUp() {
    connection = TestJSONRPCConnection(allowUnexpectedNotification: false)
  }

  override func tearDown() {
    connection.close()
  }

  func testRound() throws {
    let enc = try JSONEncoder().encode(EchoRequest(string: "a/b"))
    let dec = try JSONDecoder().decode(EchoRequest.self, from: enc)
    XCTAssertEqual("a/b", dec.string)
  }

  func testEcho() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      assertNoThrow {
        XCTAssertEqual(try resp.get(), "hello!")
      }
      expectation.fulfill()
    }

    try await fulfillmentOfOrThrow([expectation])
  }

  func testMessageBuffer() async throws {
    let client = connection.client
    let clientConnection = connection.clientToServerConnection
    let expectation = self.expectation(description: "notfication received")

    await client.appendOneShotNotificationHandler { (notification: EchoNotification) in
      XCTAssertEqual(notification.string, "hello!")
      expectation.fulfill()
    }

    let notification1 = try JSONEncoder().encode(JSONRPCMessage.notification(EchoNotification(string: "hello!")))
    let notification2 = try JSONEncoder().encode(JSONRPCMessage.notification(EchoNotification(string: "no way!")))

    let notification1Str =
      "Content-Length: \(notification1.count)\r\n\r\n\(String(data: notification1, encoding: .utf8)!)"
    let notfication2Str =
      "Content-Length: \(notification2.count)\r\n\r\n\(String(data: notification2, encoding: .utf8)!)"

    for b in notification1Str.utf8.dropLast() {
      clientConnection.send(_rawData: [b].withUnsafeBytes { DispatchData(bytes: $0) })
    }

    clientConnection.send(
      _rawData: [notification1Str.utf8.last!, notfication2Str.utf8.first!].withUnsafeBytes { DispatchData(bytes: $0) }
    )

    try await fulfillmentOfOrThrow([expectation])

    let expectation2 = self.expectation(description: "notification received")

    await client.appendOneShotNotificationHandler { (notification: EchoNotification) in
      XCTAssertEqual(notification.string, "no way!")
      expectation2.fulfill()
    }

    for b in notfication2Str.utf8.dropFirst() {
      clientConnection.send(_rawData: [b].withUnsafeBytes { DispatchData(bytes: $0) })
    }

    try await fulfillmentOfOrThrow([expectation2])

    // Close the connection before accessing requestBuffer, which ensures we don't race.
    connection.serverToClientConnection.close()
    XCTAssert(connection.serverToClientConnection.requestBufferIsEmpty)
  }

  func testEchoError() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "response received 1")
    let expectation2 = self.expectation(description: "response received 2")

    _ = client.send(EchoError(code: nil)) { (resp) -> Void in
      do {
        assertNoThrow {
          XCTAssertEqual(try resp.get(), VoidResponse())
        }
      }
      expectation.fulfill()
    }

    _ = client.send(EchoError(code: .unknownErrorCode, message: "hey!")) { resp in
      XCTAssertEqual(resp, LSPResult<VoidResponse>.failure(ResponseError(code: .unknownErrorCode, message: "hey!")))
      expectation2.fulfill()
    }

    try await fulfillmentOfOrThrow([expectation, expectation2])
  }

  func testEchoNotification() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "notification received")

    await client.appendOneShotNotificationHandler { (notification: EchoNotification) in
      XCTAssertEqual(notification.string, "hello!")
      expectation.fulfill()
    }

    client.send(EchoNotification(string: "hello!"))

    try await fulfillmentOfOrThrow([expectation])
  }

  func testUnknownRequest() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    struct UnknownRequest: RequestType {
      static let method: String = "unknown"
      typealias Response = VoidResponse
    }

    _ = client.send(UnknownRequest()) { result in
      XCTAssertEqual(result, .failure(ResponseError.methodNotFound("unknown")))
      expectation.fulfill()
    }

    try await fulfillmentOfOrThrow([expectation])
  }

  func testUnknownNotification() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "notification received")

    struct UnknownNotification: NotificationType {
      static let method: String = "unknown"
    }

    client.send(UnknownNotification())

    // Nothing bad should happen; check that the next request works.

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      assertNoThrow {
        XCTAssertEqual(try resp.get(), "hello!")
      }
      expectation.fulfill()
    }

    try await fulfillmentOfOrThrow([expectation])
  }

  func testUnexpectedResponse() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    // response to unknown request
    connection.clientToServerConnection.sendReply(.success(VoidResponse()), id: .string("unknown"))

    // Nothing bad should happen; check that the next request works.

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      assertNoThrow {
        XCTAssertEqual(try resp.get(), "hello!")
      }
      expectation.fulfill()
    }

    try await fulfillmentOfOrThrow([expectation])
  }

  func testSendAfterClose() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "notification received")

    connection.clientToServerConnection.close()

    client.send(EchoNotification(string: "hi"))
    _ = client.send(EchoRequest(string: "yo")) { result in
      XCTAssertEqual(result, .failure(ResponseError.serverCancelled))
      expectation.fulfill()
    }

    connection.clientToServerConnection.sendReply(.success(VoidResponse()), id: .number(1))

    connection.clientToServerConnection.close()
    connection.clientToServerConnection.close()

    try await fulfillmentOfOrThrow([expectation])
  }

  func testSendBeforeClose() async throws {
    let client = connection.client
    let server = connection.server

    let expectation = self.expectation(description: "received notification")
    await client.appendOneShotNotificationHandler { (notification: EchoNotification) in
      expectation.fulfill()
    }

    server.client.send(EchoNotification(string: "about to close!"))
    connection.serverToClientConnection.close()

    try await fulfillmentOfOrThrow([expectation])
  }

  /// We can explicitly close a connection, but the connection also
  /// automatically closes itself if the pipe is closed (or has an error).
  /// DispatchIO can make its callback at any time, so this test is to try to
  /// provoke a race between those things and ensure the closeHandler is called
  /// exactly once.
  func testCloseRace() async throws {
    for _ in 0...100 {
      let to = Pipe()
      let from = Pipe()
      let expectation = self.expectation(description: "closed")
      expectation.assertForOverFulfill = true

      let conn = JSONRPCConnection(
        name: "test",
        protocol: MessageRegistry(requests: [], notifications: []),
        inFD: to.fileHandleForReading,
        outFD: from.fileHandleForWriting
      )

      final class DummyHandler: MessageHandler {
        func handle(_: some NotificationType) {}
        func handle<Request: RequestType>(
          _ request: Request,
          id: RequestID,
          reply: @escaping (LSPResult<Request.Response>) -> Void
        ) {}
      }

      conn.start(
        receiveHandler: DummyHandler(),
        closeHandler: {
          // We get an error from XCTest if this is fulfilled more than once.
          expectation.fulfill()

          // Keep the pipes alive until we close the connection.
          withExtendedLifetime((to, from)) {}
        }
      )

      to.fileHandleForWriting.closeFile()
      #if os(Windows)
      // 1 ms was chosen for simplicity.
      Sleep(1)
      #else
      // 100 us was chosen empirically to encourage races.
      usleep(100)
      #endif
      conn.close()

      try await fulfillmentOfOrThrow([expectation])
      withExtendedLifetime(conn) {}
    }
  }

  func testMessageWithMissingParameter() async throws {
    let expectation = self.expectation(description: "Received ShowMessageNotification")
    await connection.client.appendOneShotNotificationHandler { (notification: ShowMessageNotification) in
      XCTAssertEqual(notification.type, .error)
      expectation.fulfill()
    }

    let messageContents = """
      {
        "method": "test_server/echo_note",
        "jsonrpc": "2.0",
        "params": {}
      }
      """
    connection.clientToServerConnection.send(message: messageContents)

    try await fulfillmentOfOrThrow([expectation])
  }
}

fileprivate extension JSONRPCConnection {
  func send(message: String) {
    let messageWithHeader = "Content-Length: \(message.utf8.count)\r\n\r\n\(message)".data(using: .utf8)!
    messageWithHeader.withUnsafeBytes { bytes in
      send(_rawData: DispatchData(bytes: bytes))
    }
  }
}
