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

final class OnTypeFormattingTests: XCTestCase {
  func testOnlyFormatsSpecifiedLine() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      1️⃣// do stuff
      }
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DocumentOnTypeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"],
        ch: "\n",
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

  func testFormatsFullLineAndDoesNotFormatNextLine() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = """
      func foo() {
      if let SomeReallyLongVar =     Some.More.Stuff(), let a =     myfunc() 1️⃣{
      }
      }
      """
    let positions = testClient.openDocument(source, uri: uri)

    let response = try await testClient.send(
      DocumentOnTypeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"],
        ch: "{",
        options: FormattingOptions(tabSize: 4, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    let (_, unmarkedSource) = extractMarkers(source)
    let formattedSource = apply(edits: edits, to: unmarkedSource)

    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })
    XCTAssertEqual(
      formattedSource,
      """
      func foo() {
          if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      }
      }
      """
    )
  }

  /// Should not remove empty lines when formatting is triggered on a new empty line.
  /// Otherwise could mess up writing code. You'd write {} and try to go into the braces to write more code,
  /// only for on-type formatting to immediately close the braces again.
  func testDoesNothingWhenInAnEmptyLine() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() {
      if let SomeReallyLongVar =     Some.More.Stuff(), let a =     myfunc() {


      1️⃣


      }
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DocumentOnTypeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"],
        ch: "\n",
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    XCTAssertEqual(
      edits,
      []
    )
  }
}
