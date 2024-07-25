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
import SKTestSupport
import SourceKitLSP
import XCTest

final class DocumentColorTests: XCTestCase {
  // MARK: - Helpers

  private func performDocumentColorRequest(text: String) async throws -> [ColorInformation] {
    let testClient = try await TestSourceKitLSPClient()

    let uri = DocumentURI(for: .swift)

    testClient.openDocument(text, uri: uri)

    let request = DocumentColorRequest(textDocument: TextDocumentIdentifier(uri))
    return try await testClient.send(request)
  }

  private func performColorPresentationRequest(
    text: String,
    color: Color,
    range: Range<Position>
  ) async throws -> [ColorPresentation] {
    let testClient = try await TestSourceKitLSPClient()

    let uri = DocumentURI(for: .swift)

    testClient.openDocument(text, uri: uri)

    let request = ColorPresentationRequest(
      textDocument: TextDocumentIdentifier(uri),
      color: color,
      range: range
    )
    return try await testClient.send(request)
  }

  // MARK: - Tests

  func testEmptyText() async throws {
    let colors = try await performDocumentColorRequest(text: "")
    XCTAssertEqual(colors, [])
  }

  func testSimple() async throws {
    let text = #"""
      #colorLiteral(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
      """#
    let colors = try await performDocumentColorRequest(text: text)

    XCTAssertEqual(
      colors,
      [
        ColorInformation(
          range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 58),
          color: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        )
      ]
    )
  }

  func testWeirdWhitespace() async throws {
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
    let colors = try await performDocumentColorRequest(text: text)

    XCTAssertEqual(
      colors,
      [
        ColorInformation(
          range: Position(line: 0, utf16index: 10)..<Position(line: 0, utf16index: 61),
          color: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
        ),
        ColorInformation(
          range: Position(line: 1, utf16index: 10)..<Position(line: 13, utf16index: 5),
          color: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
        ),
      ]
    )
  }

  func testPresentation() async throws {
    let text = """
      let x = #colorLiteral(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5);
      """
    let color = Color(red: 0, green: 1, blue: 4 - .pi, alpha: 0.3)
    let range = Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 58)
    let newText = """
      #colorLiteral(red: \(color.red), green: \(color.green), blue: \(color.blue), alpha: \(color.alpha))
      """
    let presentations = try await performColorPresentationRequest(text: text, color: color, range: range)
    XCTAssertEqual(presentations.count, 1)
    let presentation = presentations[0]
    XCTAssertEqual(presentation.label, "Color Literal")
    XCTAssertEqual(presentation.textEdit?.range, range)
    XCTAssertEqual(presentation.textEdit?.newText, newText)
  }
}
