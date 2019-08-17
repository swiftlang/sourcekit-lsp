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

import LanguageServerProtocolJSONRPC
import LanguageServerProtocol
import SKTestSupport
import XCTest

// Workaround ambiguity with Foundation.
typealias Notification = LanguageServerProtocol.Notification

class ConnectionTests: XCTestCase {

  var connection: TestJSONRPCConnection! = nil

  override func setUp() {
    connection = TestJSONRPCConnection()
  }

  override func tearDown() {
    connection.close()
  }

  func testRound() {
    let enc = try! JSONEncoder().encode(EchoRequest(string: "a/b"))
    let dec = try! JSONDecoder().decode(EchoRequest.self, from: enc)
    XCTAssertEqual("a/b", dec.string)
  }

  func testEcho() {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      XCTAssertEqual(try! resp.get(), "hello!")
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10)

    XCTAssertEqual(connection.serverConnection._requestBuffer, [])
  }

  func testMessageBuffer() {
    let client = connection.client
    let clientConnection = connection.clientConnection
    let expectation = self.expectation(description: "note received")

    client.handleNextNotification { (note: Notification<EchoNotification>) in
      XCTAssertEqual(note.params.string, "hello!")
      expectation.fulfill()
    }

    let note1 = try! JSONEncoder().encode(JSONRPCMessage.notification(EchoNotification(string: "hello!")))
    let note2 = try! JSONEncoder().encode(JSONRPCMessage.notification(EchoNotification(string: "no way!")))

    let note1Str: String = "Content-Length: \(note1.count)\r\n\r\n\(String(data: note1, encoding: .utf8)!)"
    let note2Str: String = "Content-Length: \(note2.count)\r\n\r\n\(String(data: note2, encoding: .utf8)!)"

    for b in note1Str.utf8.dropLast() {
      clientConnection.send(_rawData: [b].withUnsafeBytes { DispatchData(bytes: $0) })
    }

    clientConnection.send(_rawData: [note1Str.utf8.last!, note2Str.utf8.first!].withUnsafeBytes { DispatchData(bytes: $0) })

    waitForExpectations(timeout: 10)
    XCTAssertEqual(connection.serverConnection._requestBuffer, [note2Str.utf8.first!])

    let expectation2 = self.expectation(description: "note received")

    client.handleNextNotification { (note: Notification<EchoNotification>) in
      XCTAssertEqual(note.params.string, "no way!")
      expectation2.fulfill()
    }

    for b in note2Str.utf8.dropFirst() {
      clientConnection.send(_rawData: [b].withUnsafeBytes { DispatchData(bytes: $0) })
    }

    waitForExpectations(timeout: 10)
    XCTAssertEqual(connection.serverConnection._requestBuffer, [])
  }

  func testEchoError() {
    let client = connection.client
    let expectation = self.expectation(description: "response received 1")
    let expectation2 = self.expectation(description: "response received 2")

    _ = client.send(EchoError(code: nil)) { resp in
      XCTAssertEqual(try! resp.get(), VoidResponse())
      expectation.fulfill()
    }

    _ = client.send(EchoError(code: .unknownErrorCode, message: "hey!")) { resp in
      XCTAssertEqual(resp, LSPResult<VoidResponse>.failure(ResponseError(code: .unknownErrorCode, message: "hey!")))
      expectation2.fulfill()
    }

    waitForExpectations(timeout: 10)

    XCTAssertEqual(connection.serverConnection._requestBuffer, [])
  }

  func testEchoNote() {
    let client = connection.client
    let expectation = self.expectation(description: "note received")

    client.handleNextNotification { (note: Notification<EchoNotification>) in
      XCTAssertEqual(note.params.string, "hello!")
      expectation.fulfill()
    }

    client.send(EchoNotification(string: "hello!"))

    waitForExpectations(timeout: 10)

    XCTAssertEqual(connection.serverConnection._requestBuffer, [])
  }

  func testUnknownRequest() {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    struct UnknownRequest: RequestType {
      static let method: String = "unknown"
      typealias Response = VoidResponse
    }

    _ = client.send(UnknownRequest()) { result in
      XCTAssertEqual(result.failure, ResponseError.methodNotFound("unknown"))
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10)
  }

  func testUnknownNotification() {
    let client = connection.client
    let expectation = self.expectation(description: "note received")

    struct UnknownNote: NotificationType {
      static let method: String = "unknown"
    }

    _ = client.send(UnknownNote())

    // Nothing bad should happen; check that the next request works.

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      XCTAssertEqual(try! resp.get(), "hello!")
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10)
  }

  func testUnexpectedResponse() {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    // response to unknown request
    connection.clientConnection.sendReply(.success(VoidResponse()), id: .string("unknown"))

    // Nothing bad should happen; check that the next request works.

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      XCTAssertEqual(try! resp.get(), "hello!")
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10)
  }

  func testSendAfterClose() {
    let client = connection.client
    let expectation = self.expectation(description: "note received")

    connection.clientConnection.close()

    client.send(EchoNotification(string: "hi"))
    _ = client.send(EchoRequest(string: "yo")) { result in
      XCTAssertEqual(result.failure, ResponseError.cancelled)
      expectation.fulfill()
    }

    connection.clientConnection.sendReply(.success(VoidResponse()), id: .number(1))

    connection.clientConnection.close()
    connection.clientConnection.close()

    waitForExpectations(timeout: 10)
  }
}
