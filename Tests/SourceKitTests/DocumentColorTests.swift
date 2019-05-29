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
import SKTestSupport
import XCTest

@testable import LanguageServerProtocol
@testable import SourceKit

final class DocumentColorTests: XCTestCase {
  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  var workspace: Workspace! = nil

  override func tearDown() {
    workspace = nil
    sk = nil
    connection = nil
  }

  func initialize() {
    connection = TestSourceKitServer()
    sk = connection.client
    let documentCapabilities = TextDocumentClientCapabilities()
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURL: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))

    workspace = connection.server!.workspace!
  }

  func getDocumentColorRequest(text: String) -> DocumentColorRequest {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true

    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: text)))

    return DocumentColorRequest(textDocument: TextDocumentIdentifier(url))
  }

  func getColorPresentationRequest(text: String, color: Color, range: Range<Position>) -> ColorPresentationRequest {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true

    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: text)))

    return ColorPresentationRequest(
      textDocument: TextDocumentIdentifier(url), 
      color: color, 
      range: range)
  }

  func testEmptyText() {
    initialize()
    let request = getDocumentColorRequest(text: "")
    let colors = try! sk.sendSync(request)!
    XCTAssertEqual(colors, [])
  }

  func testSimple() {
    initialize()
    let text = #"""
    #colorLiteral(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
    """#
    let request = getDocumentColorRequest(text: text)
    let colors = try! sk.sendSync(request)!

    XCTAssertEqual(colors, [
      ColorInformation(
        range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 58), 
        color: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))
    ])
  }

  func testWeirdWhitespace() {
    initialize()
    let text = #"""
      let x = #colorLiteral(red:0.5,green:0.5,blue:0.5,alpha:0.5)
      let y = #colorLiteral(
      red
      :
      000000000000000000.5
      ,
      green
      :
    0.5
        ,
            blue
        
        :       \#t0.5,       alpha:0.5   
        )
    """#
    let request = getDocumentColorRequest(text: text)
    let colors = try! sk.sendSync(request)!

    XCTAssertEqual(colors, [
      ColorInformation(
        range: Position(line: 0, utf16index: 10)..<Position(line: 0, utf16index: 61), 
        color: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)),
      ColorInformation(
        range: Position(line: 1, utf16index: 10)..<Position(line: 13, utf16index: 5), 
        color: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)),
    ])
  }

  func testPresentation() {
    initialize()
    let text = """
    let x = #colorLiteral(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5);
    """
    let color = Color(red: 0, green: 1, blue: 3 - .pi, alpha: 0.3)
    let range = Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 58)
    let request = getColorPresentationRequest(text: text, color: color, range: range)
    let newText = """
    #colorLiteral(red: \(color.red), green: \(color.green), blue: \(color.blue), alpha: \(color.alpha))
    """
    let presentations = try! sk.sendSync(request)!
    XCTAssertEqual(presentations.count, 1)
    let presentation = presentations[0]
    XCTAssertEqual(presentation.label, "Color Literal")
    XCTAssertEqual(presentation.textEdit?.range.asRange, range)
    XCTAssertEqual(presentation.textEdit?.newText, newText)
  }
}
