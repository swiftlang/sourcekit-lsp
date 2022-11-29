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

final class InlayHintTests: XCTestCase {
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

  func performInlayHintRequest(text: String, range: Range<Position>? = nil) throws -> [InlayHint] {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    
    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .swift,
      version: 17,
      text: text
    )))

    let request = InlayHintRequest(textDocument: TextDocumentIdentifier(url), range: range)

    do {
      return try sk.sendSync(request)
    } catch let error as ResponseError where error.message.contains("unknown request: source.request.variable.type") {
      throw XCTSkip("toolchain does not support variable.type request")
    }
  }

  private func makeInlayHint(position: Position, kind: InlayHintKind, label: String) -> InlayHint {
    InlayHint(
      position: position,
      label: .string(label),
      kind: kind,
      textEdits: [
        TextEdit(range: position..<position, newText: label)
      ]
    )
  }

  func testEmpty() throws {
    let text = ""
    let hints = try performInlayHintRequest(text: text)
    XCTAssertEqual(hints, [])
  }

  func testBindings() throws {
    let text = """
    let x = 4
    var y = "test" + "123"
    """
    let hints = try performInlayHintRequest(text: text)
    XCTAssertEqual(hints, [
      makeInlayHint(
        position: Position(line: 0, utf16index: 5),
        kind: .type,
        label: ": Int"
      ),
      makeInlayHint(
        position: Position(line: 1, utf16index: 5),
        kind: .type,
        label: ": String"
      ),
    ])
  }

  func testRanged() throws {
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
    let hints = try performInlayHintRequest(text: text, range: range)
    XCTAssertEqual(hints, [
      makeInlayHint(
        position: Position(line: 6, utf16index: 10),
        kind: .type,
        label: ": Bool"
      ),
      makeInlayHint(
        position: Position(line: 7, utf16index: 12),
        kind: .type,
        label: ": Int"
      )
    ])
  }

  func testFields() throws {
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
    let hints = try performInlayHintRequest(text: text)
    XCTAssertEqual(hints, [
      makeInlayHint(
        position: Position(line: 1, utf16index: 20),
        kind: .type,
        label: ": Int"
      ),
      makeInlayHint(
        position: Position(line: 2, utf16index: 25),
        kind: .type,
        label: ": String"
      ),
      makeInlayHint(
        position: Position(line: 6, utf16index: 20),
        kind: .type,
        label: ": String"
      ),
      makeInlayHint(
        position: Position(line: 7, utf16index: 25),
        kind: .type,
        label: ": Int"
      ),
      makeInlayHint(
        position: Position(line: 11, utf16index: 25),
        kind: .type,
        label: ": Double"
      ),
    ])
  }

  func testExplicitTypeAnnotation() throws {
    let text = """
    let x: String = "abc"
    
    struct X {
      var y: Int = 34
    }
    """
    let hints = try performInlayHintRequest(text: text)
    XCTAssertEqual(hints, [])
  }

  func testClosureParams() throws {
    let text = """
    func f(x: Int) {}

    let g = { (x: Int) in }
    let h: (String) -> String = { x in x }
    let i: (Double, Double) -> Double = { (x, y) in
      x + y
    }
    """
    let hints = try performInlayHintRequest(text: text)
    XCTAssertEqual(hints, [
      makeInlayHint(
        position: Position(line: 2, utf16index: 5),
        kind: .type,
        label: ": (Int) -> ()"
      ),
      makeInlayHint(
        position: Position(line: 3, utf16index: 31),
        kind: .type,
        label: ": String"
      ),
      makeInlayHint(
        position: Position(line: 4, utf16index: 40),
        kind: .type,
        label: ": Double"
      ),
      makeInlayHint(
        position: Position(line: 4, utf16index: 43),
        kind: .type,
        label: ": Double"
      )
    ])
  }
}
