//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import XCTest

final class RangeFormattingTests: XCTestCase {
  func testOnlyFormatsSpecifiedLines() async throws {
    try await SkipUnless.toolchainContainsSwiftFormat()
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      1️⃣// do stuff2️⃣
      }
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        range: positions["1️⃣"]..<positions["2️⃣"],
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    XCTAssertEqual(
      edits,
      [
        TextEdit(range: Range(positions["1️⃣"]), newText: "    ")
      ]
    )
  }

  func testOnlyFormatsSpecifiedColumns() async throws {
    try await SkipUnless.toolchainContainsSwiftFormat()
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() {
      if let SomeReallyLongVar 1️⃣= 2️⃣    3️⃣Some.More.Stuff(), let a  =     myfunc() {
      // do stuff
      }
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        range: positions["1️⃣"]..<positions["3️⃣"],
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    XCTAssertEqual(
      edits,
      [
        TextEdit(range: positions["2️⃣"]..<positions["3️⃣"], newText: "")
      ]
    )
  }

  func testFormatsMultipleLines() async throws {
    try await SkipUnless.toolchainContainsSwiftFormat()
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      1️⃣func foo() {
      2️⃣if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      3️⃣// do stuff
      4️⃣}
      }5️⃣
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        range: positions["1️⃣"]..<positions["5️⃣"],
        options: FormattingOptions(tabSize: 4, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    XCTAssertEqual(
      edits,
      [
        TextEdit(range: Range(positions["2️⃣"]), newText: "    "),
        TextEdit(range: Range(positions["3️⃣"]), newText: "        "),
        TextEdit(range: Range(positions["4️⃣"]), newText: "    "),
      ]
    )
  }
}
