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
import SKTestSupport
import XCTest

final class HoverTests: XCTestCase {
  func testBasic() async throws {
    try await SkipUnless.sourcekitdReturnsRawDocumentationResponse()
    try await assertHover(
      """
      /// This is a doc comment for S.
      ///
      /// Details.
      struct 1️⃣S {}
      """,
      expectedContent: """
        ```swift
        struct S
        ```

        This is a doc comment for S.

        Details.
        """
    )
  }

  func testHoverTriggeredFromComment() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    let positions = testClient.openDocument(
      """
      /// Thi1️⃣s is a doc comment for S.
      ///
      /// Details.
      struct S {}
      """,
      uri: uri
    )

    let response = try await testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(url), position: positions["1️⃣"])
    )

    XCTAssertNil(response)
  }

  func testMultiCursorInfoResultsHover() async throws {
    try await assertHover(
      """
      struct Foo {
        init() {}
      }
      _ = 1️⃣Foo()
      """,
      expectedContent: """
        ## Multiple results

        ```swift
        struct Foo
        ```


        ---

        ```swift

        init()
        ```

        """
    )
  }

  func testMultiCursorInfoResultsHoverWithDocumentation() async throws {
    try await SkipUnless.sourcekitdReturnsRawDocumentationResponse()
    try await assertHover(
      """
      /// A struct
      struct Foo {
        /// The initializer
        init() {}
      }
      _ = 1️⃣Foo()
      """,
      expectedContent: """
        ## Multiple results

        ```swift
        struct Foo
        ```

        A struct

        ---

        ```swift

        init()
        ```

        The initializer
        """
    )
  }

  func testHoverNameEscapingOnFunction() async throws {
    try await SkipUnless.sourcekitdReturnsRawDocumentationResponse()
    try await assertHover(
      """
      /// this is **bold** documentation
      func 1️⃣test(_ a: Int, _ b: Int) { }
      """,
      expectedContent: ##"""
        ```swift
        func test(_ a: Int, _ b: Int)
        ```

        this is **bold** documentation
        """##
    )
  }

  func testHoverNameEscapingOnOperator() async throws {
    try await SkipUnless.sourcekitdReturnsRawDocumentationResponse()
    try await assertHover(
      """
      /// this is *italic* documentation
      func 1️⃣*%*(lhs: String, rhs: String) { }
      """,
      expectedContent: ##"""
        ```swift
        func *%* (lhs: String, rhs: String)
        ```

        this is *italic* documentation
        """##
    )
  }

  func testPrecondition() async throws {
    try await SkipUnless.sourcekitdReturnsRawDocumentationResponse()
    try await assertHover(
      """
      /// Eat an apple
      ///
      /// - Precondition: Must have an apple
      func 1️⃣eatApple() {}
      """,
      expectedContent: """
        ```swift
        func eatApple()
        ```

        Eat an apple

        - Precondition: Must have an apple
        """
    )
  }
}

private func assertHover(
  _ markedSource: String,
  expectedContent: String,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: .swift)

  let positions = testClient.openDocument(markedSource, uri: uri)

  let response = try await testClient.send(
    HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
  )

  let hover = try XCTUnwrap(response, file: file, line: line)
  XCTAssertNil(hover.range, file: file, line: line)
  guard case .markupContent(let content) = hover.contents else {
    XCTFail("hover.contents is not .markupContents", file: file, line: line)
    return
  }
  XCTAssertEqual(content.kind, .markdown, file: file, line: line)
  XCTAssertEqual(content.value, expectedContent, file: file, line: line)

}
