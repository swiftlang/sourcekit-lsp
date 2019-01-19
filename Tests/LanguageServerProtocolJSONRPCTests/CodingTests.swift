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

@testable import LanguageServerProtocolJSONRPC
import LanguageServerProtocol
import XCTest
import SKTestSupport

final class CodingTests: XCTestCase {

  func testMessageCoding() {
    checkMessageCoding(InitializeRequest(processId: 1, rootPath: "/foo", rootURL: nil, initializationOptions: nil, capabilities: ClientCapabilities(workspace: nil, textDocument: nil), trace: .off, workspaceFolders: nil), id: .number(2), json: """
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

    checkMessageCoding(InitializeRequest(processId: 1, rootPath: "/foo", rootURL: nil, initializationOptions: nil, capabilities: ClientCapabilities(workspace: nil, textDocument: nil), trace: .off, workspaceFolders: nil), id: .string("3"), json: """
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

    checkMessageCoding(CancelRequest(id: .number(1)), json: """
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
      textDocumentSync: TextDocumentSyncOptions(
        openClose: true,
        change: .incremental,
        willSave: true,
        willSaveWaitUntil: false,
        save: TextDocumentSyncOptions.SaveOptions(includeText: false)),
      completionProvider: CompletionOptions(
        resolveProvider: false,
        triggerCharacters: ["."]),
      hoverProvider: nil,
      definitionProvider: nil,
      referencesProvider: nil,
      documentHighlightProvider: nil,
      foldingRangeProvider: nil,
      codeActionProvider: nil)), id: .number(2), json: """
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
        "message" : "request cancelled"
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

    checkMessageDecodingError(MessageDecodingError.invalidRequest("message not recognized as request, response or notification"), json: """
    {"jsonrpc":"2.0","error":{"code":-32000,"message":""}}
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

    checkMessageDecodingError(MessageDecodingError.invalidParams("type mistmatch at params : Expected to decode Dictionary<String, Any> but found a number instead.", messageKind: .notification), json: """
    {"jsonrpc":"2.0","method":"$/cancelRequest","params":2}
    """)

    checkMessageDecodingError(MessageDecodingError.invalidParams("missing expected parameter: id", messageKind: .notification), json: """
    {"jsonrpc":"2.0","method":"$/cancelRequest","params":{}}
    """)

    let responseTypeCallback: Message.ResponseTypeCallback = {
      return $0 == .string("unknown") ? nil : InitializeResult.self
    }

    let info = [CodingUserInfoKey.responseTypeCallbackKey: responseTypeCallback]

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
}

private func checkMessageCoding<Request>(_ value: Request, id: RequestID, json: String, file: StaticString = #file, line: UInt = #line) where Request: RequestType & Equatable {
  checkCoding(Message.request(value, id: id), json: json, file: file, line: line) {

    guard case Message.request(let decodedValueOpaque, let decodedID) = $0, let decodedValue = decodedValueOpaque as? Request else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(id, decodedID, "requestID decoding", file: file, line: line)
    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageCoding<Notification>(_ value: Notification, json: String, file: StaticString = #file, line: UInt = #line) where Notification: NotificationType & Equatable {
  checkCoding(Message.notification(value), json: json, file: file, line: line) {

    guard case Message.notification(let decodedValueOpaque) = $0, let decodedValue = decodedValueOpaque as? Notification else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageCoding<Response>(_ value: Response, id: RequestID, json: String, file: StaticString = #file, line: UInt = #line) where Response: ResponseType & Equatable {

  let callback: Message.ResponseTypeCallback = {
    return $0 == .string("unknown") ? nil : Response.self
  }

  checkCoding(Message.response(value, id: id), json: json, userInfo: [.responseTypeCallbackKey: callback], file: file, line: line) {

    guard case Message.response(let decodedValueOpaque, let decodedID) = $0, let decodedValue = decodedValueOpaque as? Response else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(id, decodedID, "requestID decoding", file: file, line: line)
    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageCoding(_ value: ResponseError, id: RequestID, json: String, file: StaticString = #file, line: UInt = #line) {
  checkCoding(Message.errorResponse(value, id: id), json: json, file: file, line: line) {

    guard case Message.errorResponse(let decodedValue, let decodedID) = $0 else {
      XCTFail("decodedValue \($0) does not match expected \(value)", file: file, line: line)
      return
    }

    XCTAssertEqual(id, decodedID, "requestID decoding", file: file, line: line)
    XCTAssertEqual(value, decodedValue, file: file, line: line)
  }
}

private func checkMessageDecodingError(_ expected: MessageDecodingError, json: String, userInfo: [CodingUserInfoKey: Any] = [:], file: StaticString = #file, line: UInt = #line) {
  let data = json.data(using: .utf8)!
  let decoder = JSONDecoder()
  decoder.userInfo = userInfo

  do {
    _ = try decoder.decode(Message.self, from: data)
    XCTFail("expected error not seen", file: file, line: line)
  } catch let error as MessageDecodingError {
    XCTAssertEqual(expected, error, file: file, line: line)
  } catch {
    XCTFail("incorrect error seen \(error)", file: file, line: line)
  }
}
