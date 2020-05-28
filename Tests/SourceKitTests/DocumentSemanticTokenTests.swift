//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import LSPTestSupport
import SKTestSupport
import SourceKit
import XCTest

final class DocumentSemanticTokenTest: XCTestCase {
  typealias DocumentSymbolCapabilities = TextDocumentClientCapabilities.SemanticTokens

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

override func tearDown() {
  sk = nil
  connection = nil
}

func initialize(capabilities: DocumentSymbolCapabilities) {
    connection = TestSourceKitServer()
    sk = connection.client
    var documentCapabilities = TextDocumentClientCapabilities()
    documentCapabilities.semanticTokens = capabilities
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))
  }

  func performDocumentSemanticTokensRequest(text: String) -> DocumentSemanticTokenResponse {
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .swift,
      version: 17,
      text: text
    )))

    let request = DocumentSemanticTokenRequest(textDocument: TextDocumentIdentifier(url))
    return try! sk.sendSync(request)!
  }

  func range(from startTuple: (Int, Int), to endTuple: (Int, Int)) -> Range<Position> {
    let startPos = Position(line: startTuple.0, utf16index: startTuple.1)
    let endPos = Position(line: endTuple.0, utf16index: endTuple.1)
    return startPos..<endPos
  }

  func testEmpty() {
    let capabilities = DocumentSymbolCapabilities()
    initialize(capabilities: capabilities)

    let text = ""
    let symbols = performDocumentSemanticTokensRequest(text: text)
     XCTAssertEqual(symbols.data, [])
  }

  func testClassAndEnum() {
    let capabilities = DocumentSymbolCapabilities()
    initialize(capabilities: capabilities)

    let text = """
    class S {
      let x: String = ""
      let y: Int = 0

      func f(a: S) -> String {
        return "" + "x"
      }
    }
    enum En {
      case f
      case g
    }
    let test = S()
    """
    let expectedOutput = [
      0, 0, 5, 1, 0,
      0, 6, 1, 8, 0, 
      1, 2, 3, 1, 0, 
      0, 4, 1, 17, 0, 
      0, 3, 6, 6, 0, 
      1, 2, 3, 1, 0, 
      0, 4, 1, 17, 0, 
      0, 3, 3, 6, 0, 
      2, 2, 4, 1, 0, 
      0, 5, 1, 12, 0, 
      0, 2, 1, 16, 0, 
      0, 3, 1, 6, 0, 
      0, 6, 6, 6, 0, 
      1, 4, 6, 1, 0, 
      3, 0, 4, 1, 0, 
      0, 5, 2, 10, 0, 
      1, 2, 4, 1, 0, 
      1, 2, 4, 1, 0, 
      2, 0, 3, 1, 0, 
      0, 4, 4, 15, 0
    ]
    let symbols = performDocumentSemanticTokensRequest(text: text)
    XCTAssertEqual(symbols.data, expectedOutput)
  }
 }
