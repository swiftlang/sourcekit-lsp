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

import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import LSPTestSupport
import XCTest

final class CodingTests: XCTestCase {

  func testMessageCoding() {
    checkMessageCoding(InitializeRequest(processId: 1, rootPath: "/foo", rootURI: nil, initializationOptions: nil, capabilities: ClientCapabilities(workspace: nil, textDocument: nil), trace: .off, workspaceFolders: nil), id: .number(2), json: """
    {
      "id" : 2,
      "jsonrpc" : "2.0",
      "method" : "initialize",
      "params" : {
        "capabilities" : {

        },
        "processId" : 1,
        "rootPath" : "\\/foo",
        "trace" : "off"
      }
    }
    """)

    checkMessageCoding(InitializeRequest(processId: 1, rootPath: "/foo", rootURI: nil, initializationOptions: nil, capabilities: ClientCapabilities(workspace: nil, textDocument: nil), trace: .off, workspaceFolders: nil), id: .string("3"), json: """
    {
      "id" : "3",
      "jsonrpc" : "2.0",
      "method" : "initialize",
      "params" : {
        "capabilities" : {

        },
        "processId" : 1,
        "rootPath" : "\\/foo",
        "trace" : "off"
      }
    }
    """)

    checkMessageCoding(CancelRequestNotification(id: .number(1)), json: """
    {
      "jsonrpc" : "2.0",
      "method" : "$\\/cancelRequest",
      "params" : {
        "id" : 1
      }
    }
    """)

    checkMessageCoding(InitializedNotification(), json: """
    {
      "jsonrpc" : "2.0",
      "method" : "initialized",
      "params" : {

      }
    }
    """)

    checkMessageCoding(InitializeResult(capabilities: ServerCapabilities(
      textDocumentSync: .options(TextDocumentSyncOptions(
        openClose: true,
        change: .incremental,
        willSave: true,
        willSaveWaitUntil: false,
        save: .value(TextDocumentSyncOptions.SaveOptions(includeText: false))
      )),
      completionProvider: CompletionOptions(
        resolveProvider: false,
        triggerCharacters: ["."]))), id: .number(2), json: """
    {
      "id" : 2,
      "jsonrpc" : "2.0",
      "result" : {
        "capabilities" : {
          "completionProvider" : {
            "resolveProvider" : false,
            "triggerCharacters" : [
              "."
            ]
          },
          "textDocumentSync" : {
            "change" : 2,
            "openClose" : true,
            "save" : {
              "includeText" : false
            },
            "willSave" : true,
            "willSaveWaitUntil" : false
          }
        }
      }
    }
    """)

    checkMessageCoding(ResponseError.cancelled, id: .number(2), json: """
    {
      "error" : {
        "code" : -32800,
        "message" : "request cancelled by client"
      },
      "id" : 2,
      "jsonrpc" : "2.0"
    }
    """)

    checkMessageCoding(ResponseError.methodNotFound("asdf"), id: .number(2), json: """
    {
      "error" : {
        "code" : -32601,
        "message" : "method not found: asdf"
      },
      "id" : 2,
      "jsonrpc" : "2.0"
    }
    """)

    checkMessageCoding(ResponseError.cancelled, id: nil, json: """
    {
      "error" : {
        "code" : -32800,
        "message" : "request cancelled by client"
      },
      "id" : null,
      "jsonrpc" : "2.0"
    }
    """)
  }

  func testMessageDecodingError() {
    // Note: JSON parsing errors are caught at a higher level.

    checkMessageDecodingError(MessageDecodingError.invalidRequest("jsonrpc version must be 2.0"), json: """
    {}
    """)

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification"), json: """
    {"jsonrpc":"2.0"}
    """)

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification"), json: """
    {"jsonrpc":"2.0","params":{}}
    """)

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification"), json: """
    {"jsonrpc":"2.0","result":{}}
    """)

    checkMessageDecodingError(MessageDecodingError.methodNotFound("unknown", messageKind: .notification), json: """
    {"jsonrpc":"2.0","method":"unknown"}
    """)

    checkMessageDecodingError(MessageDecodingError.methodNotFound("unknown", id: .number(2), messageKind: .request), json: """
    {"jsonrpc":"2.0","id":2,"method":"unknown"}
    """)

    checkMessageDecodingError(MessageDecodingError.methodNotFound("initialized", id: .number(2), messageKind: .request), json: """
    {"jsonrpc":"2.0","id":2,"method":"initialized"}
    """)

    checkMessageDecodingError(MessageDecodingError.methodNotFound("initialize", messageKind: .notification), json: """
    {"jsonrpc":"2.0","method":"initialize"}
    """)

    checkMessageDecodingError(MessageDecodingError.invalidParams("missing expected parameter: params", messageKind: .notification), json: """
    {"jsonrpc":"2.0","method":"$/cancelRequest"}
    """)

    checkMessageDecodingError(MessageDecodingError.invalidParams("type mismatch at params :", messageKind: .notification), json: """
    {"jsonrpc":"2.0","method":"$/cancelRequest","params":2}
    """)

    checkMessageDecodingError(MessageDecodingError.invalidParams("missing expected parameter: id", messageKind: .notification), json: """
    {"jsonrpc":"2.0","method":"$/cancelRequest","params":{}}
    """)

    let responseTypeCallback: JSONRPCMessage.ResponseTypeCallback = {
      return $0 == .string("unknown") ? nil : InitializeResult.self
    }

    let info = defaultCodingInfo.merging([CodingUserInfoKey.responseTypeCallbackKey: responseTypeCallback]) { (_, new) in new }

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification", id: .number(2)), json: """
    {"jsonrpc":"2.0","id":2,"params":{}}
    """, userInfo: info)

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification"), json: """
    {"jsonrpc":"2.0","params":{}}
    """, userInfo: info)

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification", id: .string("3")), json: """
    {"jsonrpc":"2.0","id":"3","params":{}}
    """, userInfo: info)

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification", id: .string("unknown")), json: """
    {"jsonrpc":"2.0","id":"unknown","params":{}}
    """, userInfo: info)

    checkMessageDecodingError(MessageDecodingError.invalidParams("missing expected parameter: capabilities", id: .number(2), messageKind: .response), json: """
    {"jsonrpc":"2.0","id":2,"result":{}}
    """, userInfo: info)
  }

  // SR-16095
  func testDecodeShutdownWithoutParams() {
    let json = """
      {
        "id" : 1,
        "jsonrpc" : "2.0",
        "method" : "shutdown"
      }
      """

    let decoder = JSONDecoder()
    decoder.userInfo = defaultCodingInfo
    let decodedValue = try! decoder.decode(JSONRPCMessage.self, from: json.data(using: .utf8)!)

    guard case JSONRPCMessage.request(let decodedValueOpaque, let decodedID) = decodedValue, let decodedRequest = decodedValueOpaque as? ShutdownRequest else {
      XCTFail("decodedValue \(decodedValue) is not a ShutdownRequest")
      return
    }

    XCTAssertEqual(.number(1), decodedID, "expected request ID 1")
    XCTAssertEqual(ShutdownRequest(), decodedRequest)
  }
}

let defaultCodingInfo: [CodingUserInfoKey: Any] = [CodingUserInfoKey.messageRegistryKey:MessageRegistry.lspProtocol]

private func checkMessageCoding<Request>(_ value: Request, id: RequestID, json: String, file: StaticString = #filePath, line: UInt = #line) where Request: RequestType & Equatable {
  checkCoding(JSONRPCMessage.request(value, id: id), json: json, userInfo: defaultCodingInfo, file: file, line: line) {

    guard case JSONRPCMessage.request(let decodedValueOpaque, let decodedID) = $0, let decodedValue = decodedValueOpaque as? Request else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(id, decodedID, "requestID decoding", file: file, line: line)
    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageCoding<Notification>(_ value: Notification, json: String, file: StaticString = #filePath, line: UInt = #line) where Notification: NotificationType & Equatable {
  checkCoding(JSONRPCMessage.notification(value), json: json, userInfo: defaultCodingInfo, file: file, line: line) {

    guard case JSONRPCMessage.notification(let decodedValueOpaque) = $0, let decodedValue = decodedValueOpaque as? Notification else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageCoding<Response>(_ value: Response, id: RequestID, json: String, file: StaticString = #filePath, line: UInt = #line) where Response: ResponseType & Equatable {

  let callback: JSONRPCMessage.ResponseTypeCallback = {
    return $0 == .string("unknown") ? nil : Response.self
  }

  var codingInfo = defaultCodingInfo
  codingInfo[.responseTypeCallbackKey] = callback

  checkCoding(JSONRPCMessage.response(value, id: id), json: json, userInfo: codingInfo, file: file, line: line) {

    guard case JSONRPCMessage.response(let decodedValueOpaque, let decodedID) = $0, let decodedValue = decodedValueOpaque as? Response else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(id, decodedID, "requestID decoding", file: file, line: line)
    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageCoding(_ value: ResponseError, id: RequestID?, json: String, file: StaticString = #filePath, line: UInt = #line) {
  checkCoding(JSONRPCMessage.errorResponse(value, id: id), json: json, userInfo: defaultCodingInfo, file: file, line: line) {

    guard case JSONRPCMessage.errorResponse(let decodedValue, let decodedID) = $0 else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(id, decodedID, "requestID decoding", file: file, line: line)
    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageDecodingError(_ expected: MessageDecodingError, json: String, userInfo: [CodingUserInfoKey: Any] = defaultCodingInfo, file: StaticString = #filePath, line: UInt = #line) {
  let data = json.data(using: .utf8)!
  let decoder = JSONDecoder()
  decoder.userInfo = userInfo

  do {
    _ = try decoder.decode(JSONRPCMessage.self, from: data)
    XCTFail("expected error not seen", file: file, line: line)
  } catch let error as MessageDecodingError {
    XCTAssertEqual(expected.code, error.code, file: file, line: line)
    XCTAssertEqual(expected.id, error.id, file: file, line: line)
    XCTAssertTrue(error.message.hasPrefix(expected.message),
      "message expected to start with \(expected.message); got \(error.message)", file: file, line: line)
  } catch {
    XCTFail("incorrect error seen \(error)", file: file, line: line)
  }
}
