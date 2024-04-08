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

import LSPTestSupport
import LanguageServerProtocol
@_spi(Testing) import LanguageServerProtocolJSONRPC
import XCTest

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

  func testEcho() {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      assertNoThrow {
        XCTAssertEqual(try resp.get(), "hello!")
      }
      expectation.fulfill()
    }

    waitForExpectations(timeout: defaultTimeout)
  }

  func testMessageBuffer() async throws {
    let client = connection.client
    let clientConnection = connection.clientToServerConnection
    let expectation = self.expectation(description: "note received")

    await client.appendOneShotNotificationHandler { (note: EchoNotification) in
      XCTAssertEqual(note.string, "hello!")
      expectation.fulfill()
    }

    let note1 = try JSONEncoder().encode(JSONRPCMessage.notification(EchoNotification(string: "hello!")))
    let note2 = try JSONEncoder().encode(JSONRPCMessage.notification(EchoNotification(string: "no way!")))

    let note1Str: String = "Content-Length: \(note1.count)\r\n\r\n\(String(data: note1, encoding: .utf8)!)"
    let note2Str: String = "Content-Length: \(note2.count)\r\n\r\n\(String(data: note2, encoding: .utf8)!)"

    for b in note1Str.utf8.dropLast() {
      clientConnection.send(_rawData: [b].withUnsafeBytes { DispatchData(bytes: $0) })
    }

    clientConnection.send(
      _rawData: [note1Str.utf8.last!, note2Str.utf8.first!].withUnsafeBytes { DispatchData(bytes: $0) }
    )

    try await fulfillmentOfOrThrow([expectation])

    let expectation2 = self.expectation(description: "note received")

    await client.appendOneShotNotificationHandler { (note: EchoNotification) in
      XCTAssertEqual(note.string, "no way!")
      expectation2.fulfill()
    }

    for b in note2Str.utf8.dropFirst() {
      clientConnection.send(_rawData: [b].withUnsafeBytes { DispatchData(bytes: $0) })
    }

    try await fulfillmentOfOrThrow([expectation2])

    // Close the connection before accessing requestBuffer, which ensures we don't race.
    connection.serverToClientConnection.close()
    XCTAssert(connection.serverToClientConnection.requestBufferIsEmpty)
  }

  func testEchoError() {
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

    waitForExpectations(timeout: defaultTimeout)
  }

  func testEchoNote() async throws {
    let client = connection.client
    let expectation = self.expectation(description: "note received")

    await client.appendOneShotNotificationHandler { (note: EchoNotification) in
      XCTAssertEqual(note.string, "hello!")
      expectation.fulfill()
    }

    client.send(EchoNotification(string: "hello!"))

    try await fulfillmentOfOrThrow([expectation])
  }

  func testUnknownRequest() {
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

    waitForExpectations(timeout: defaultTimeout)
  }

  func testUnknownNotification() {
    let client = connection.client
    let expectation = self.expectation(description: "note received")

    struct UnknownNote: NotificationType {
      static let method: String = "unknown"
    }

    client.send(UnknownNote())

    // Nothing bad should happen; check that the next request works.

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      assertNoThrow {
        XCTAssertEqual(try resp.get(), "hello!")
      }
      expectation.fulfill()
    }

    waitForExpectations(timeout: defaultTimeout)
  }

  func testUnexpectedResponse() {
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

    waitForExpectations(timeout: defaultTimeout)
  }

  func testSendAfterClose() {
    let client = connection.client
    let expectation = self.expectation(description: "note received")

    connection.clientToServerConnection.close()

    client.send(EchoNotification(string: "hi"))
    _ = client.send(EchoRequest(string: "yo")) { result in
      XCTAssertEqual(result, .failure(ResponseError.serverCancelled))
      expectation.fulfill()
    }

    connection.clientToServerConnection.sendReply(.success(VoidResponse()), id: .number(1))

    connection.clientToServerConnection.close()
    connection.clientToServerConnection.close()

    waitForExpectations(timeout: defaultTimeout)
  }

  func testSendBeforeClose() async throws {
    let client = connection.client
    let server = connection.server

    let expectation = self.expectation(description: "received notification")
    await client.appendOneShotNotificationHandler { (note: EchoNotification) in
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
  func testCloseRace() {
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

          // FIXME: keep the pipes alive until we close the connection. This
          // should be fixed systemically.
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

      withExtendedLifetime(conn) {
        waitForExpectations(timeout: defaultTimeout)
      }
    }
  }

  func testMessageWithMissingParameter() async throws {
    let expectation = self.expectation(description: "Received ShowMessageNotification")
    await connection.client.appendOneShotNotificationHandler { (note: ShowMessageNotification) in
      XCTAssertEqual(note.type, .error)
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

    try await self.fulfillmentOfOrThrow([expectation])
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
