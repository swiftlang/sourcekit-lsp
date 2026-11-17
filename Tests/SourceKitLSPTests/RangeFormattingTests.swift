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

@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SKTestSupport
import SourceKitLSP
import XCTest

final class RangeFormattingTests: SourceKitLSPTestCase {
  func testOnlyFormatsSpecifiedLines() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      1️⃣// do stuff2️⃣
      }
      }
      """
    let positions = testClient.openDocument(source, uri: uri)

    let response = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        range: positions["1️⃣"]..<positions["2️⃣"],
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    let (_, unmarkedSource) = extractMarkers(source)
    let formattedSource = apply(edits: edits, to: unmarkedSource)
    let expected = try await runSwiftFormat(
      on: unmarkedSource,
      arguments: [
        "--configuration", #"{"version":1,"tabWidth":2,"indentation":{"spaces":2}}"#,
        "--offsets", "78:88",
      ]
    )

    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, unmarkedSource)
    XCTAssertTrue(
      formattedSource.hasPrefix("func foo() {\nif let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {\n")
    )
    XCTAssertTrue(formattedSource.hasSuffix("\n}\n}"))
  }

  func testOnlyFormatsSpecifiedColumns() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = """
      func foo() {
      if let SomeReallyLongVar 1️⃣=     2️⃣Some.More.Stuff(), let a  =     myfunc() {
      // do stuff
      }
      }
      """
    let positions = testClient.openDocument(source, uri: uri)

    let response = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        range: positions["1️⃣"]..<positions["2️⃣"],
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    let (_, unmarkedSource) = extractMarkers(source)
    let formattedSource = apply(edits: edits, to: unmarkedSource)
    let expected = try await runSwiftFormat(
      on: unmarkedSource,
      arguments: [
        "--configuration", #"{"version":1,"tabWidth":2,"indentation":{"spaces":2}}"#,
        "--offsets", "38:43",
      ]
    )

    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, unmarkedSource)
    XCTAssertTrue(formattedSource.contains("let a  =     myfunc() {"))
  }

  func testFormatsMultipleLines() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = """
      1️⃣func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      // do stuff
      }
      }2️⃣
      """
    let positions = testClient.openDocument(source, uri: uri)

    let response = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        range: positions["1️⃣"]..<positions["2️⃣"],
        options: FormattingOptions(tabSize: 4, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    let (_, unmarkedSource) = extractMarkers(source)
    let formattedSource = apply(edits: edits, to: unmarkedSource)
    let expected = try await runSwiftFormat(
      on: unmarkedSource,
      arguments: [
        "--configuration", #"{"version":1,"tabWidth":4,"indentation":{"spaces":4}}"#,
        "--offsets", "0:92",
      ]
    )

    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, unmarkedSource)
  }
}
