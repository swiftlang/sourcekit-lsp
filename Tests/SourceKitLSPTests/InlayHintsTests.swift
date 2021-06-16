//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import LSPTestSupport
import SKTestSupport
import SourceKitLSP
import XCTest

final class InlayHintsTests: XCTestCase {
  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  override func tearDown() {
    sk = nil
    connection = nil
  }

  override func setUp() {
    connection = TestSourceKitServer()
    sk = connection.client
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
      trace: .off,
      workspaceFolders: nil
    ))
  }

  func performInlayHintsRequest(text: String, range: Range<Position>? = nil) -> [InlayHint] {
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    
    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .swift,
      version: 17,
      text: text
    )))

    let request = InlayHintsRequest(textDocument: TextDocumentIdentifier(url), range: range)
    return try! sk.sendSync(request)
  }

  func testEmpty() {
    let text = ""
    let hints = performInlayHintsRequest(text: text)
    XCTAssertEqual(hints, [])
  }

  func testBindings() {
    let text = """
    let x = 4
    var y = "test" + "123"
    """
    let hints = performInlayHintsRequest(text: text)
    XCTAssertEqual(hints, [
      InlayHint(
        position: Position(line: 0, utf16index: 5),
        category: .type,
        label: "Int"
      ),
      InlayHint(
        position: Position(line: 1, utf16index: 5),
        category: .type,
        label: "String"
      ),
    ])
  }

  func testRanged() {
    let text = """
    func square(_ x: Double) -> Double {
      let result = x * x
      return result
    }

    func collatz(_ n: Int) -> Int {
      let even = n % 2 == 0
      let result = even ? (n / 2) : (3 * n + 1)
      return result
    }
    """
    let range = Position(line: 6, utf16index: 0)..<Position(line: 9, utf16index: 0)
    let hints = performInlayHintsRequest(text: text, range: range)
    XCTAssertEqual(hints, [
      InlayHint(
        position: Position(line: 6, utf16index: 10),
        category: .type,
        label: "Bool"
      ),
      InlayHint(
        position: Position(line: 7, utf16index: 12),
        category: .type,
        label: "Int"
      )
    ])
  }

  func testFields() {
    let text = """
    class X {
      let instanceMember = 3
      static let staticMember = "abc"
    }

    struct Y {
      var instanceMember = "def" + "ghi"
      static let staticMember = 1 + 2
    }

    enum Z {
      static let staticMember = 3.0
    }
    """
    let hints = performInlayHintsRequest(text: text)
    XCTAssertEqual(hints, [
      InlayHint(
        position: Position(line: 1, utf16index: 20),
        category: .type,
        label: "Int"
      ),
      InlayHint(
        position: Position(line: 2, utf16index: 25),
        category: .type,
        label: "String"
      ),
      InlayHint(
        position: Position(line: 6, utf16index: 20),
        category: .type,
        label: "String"
      ),
      InlayHint(
        position: Position(line: 7, utf16index: 25),
        category: .type,
        label: "Int"
      ),
      InlayHint(
        position: Position(line: 11, utf16index: 25),
        category: .type,
        label: "Double"
      ),
    ])
  }

  func testExplicitTypeAnnotation() {
    let text = """
    let x: String = "abc"
    
    struct X {
      var y: Int = 34
    }
    """
    let hints = performInlayHintsRequest(text: text)
    XCTAssertEqual(hints, [])
  }

  func testClosureParams() {
    let text = """
    func f(x: Int) {}

    let g = { (x: Int) in }
    let h: (String) -> String = { x in x }
    let i: (Double, Double) -> Double = { (x, y) in
      x + y
    }
    """
    let hints = performInlayHintsRequest(text: text)
    XCTAssertEqual(hints, [
      InlayHint(
        position: Position(line: 3, utf16index: 31),
        category: .type,
        label: "String"
      ),
      InlayHint(
        position: Position(line: 4, utf16index: 40),
        category: .type,
        label: "Double"
      ),
      InlayHint(
        position: Position(line: 4, utf16index: 43),
        category: .type,
        label: "Double"
      )
    ])
  }
}
