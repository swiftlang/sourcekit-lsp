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

import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import XCTest

final class HoverTests: XCTestCase {
  func testHover() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.openDocument(
      """
      /// This is a doc comment for S.
      ///
      /// Details.
      struct S {}
      """,
      uri: uri
    )

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 3, utf16index: 7)
        )
      )

      XCTAssertNotNil(resp)
      if let hover = resp {
        XCTAssertNil(hover.range)
        guard case .markupContent(let content) = hover.contents else {
          XCTFail("hover.contents is not .markupContents")
          return
        }
        XCTAssertEqual(content.kind, .markdown)
        XCTAssertEqual(
          content.value,
          """
          S
          ```swift
          struct S
          ```

          ---
          This is a doc comment for S.

          ### Discussion

          Details.
          """
        )
      }
    }

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 0, utf16index: 7)
        )
      )

      XCTAssertNil(resp)
    }
  }

  func testMultiCursorInfoResultsHover() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      struct Foo {
        init() {}
      }
      _ = 1️⃣Foo()
      """,
      uri: uri
    )

    let response = try await testClient.send(
      HoverRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    guard case .markupContent(let content) = response?.contents else {
      XCTFail("hover.contents is not .markupContents")
      return
    }
    XCTAssertEqual(content.kind, .markdown)
    XCTAssertEqual(
      content.value,
      """
      Foo
      ```swift
      struct Foo
      ```

      ---

      # Alternative result
      init()
      ```swift
      init()
      ```

      ---

      """
    )
  }

  func testHoverNameEscaping() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(
      """
      /// this is **bold** documentation
      func test(_ a: Int, _ b: Int) { }
      /// this is *italic* documentation
      func *%*(lhs: String, rhs: String) { }
      """,
      uri: uri
    )

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 1, utf16index: 7)
        )
      )

      XCTAssertNotNil(resp)
      if let hover = resp {
        XCTAssertNil(hover.range)
        guard case .markupContent(let content) = hover.contents else {
          XCTFail("hover.contents is not .markupContents")
          return
        }
        XCTAssertEqual(content.kind, .markdown)
        XCTAssertEqual(
          content.value,
          ##"""
          test(\_:\_:)
          ```swift
          func test(_ a: Int, _ b: Int)
          ```

          ---
          this is **bold** documentation
          """##
        )
      }
    }

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 3, utf16index: 7)
        )
      )

      XCTAssertNotNil(resp)
      if let hover = resp {
        XCTAssertNil(hover.range)
        guard case .markupContent(let content) = hover.contents else {
          XCTFail("hover.contents is not .markupContents")
          return
        }
        XCTAssertEqual(content.kind, .markdown)
        XCTAssertEqual(
          content.value,
          ##"""
          \*%\*(\_:\_:)
          ```swift
          func *%* (lhs: String, rhs: String)
          ```

          ---
          this is *italic* documentation
          """##
        )
      }
    }
  }

}
