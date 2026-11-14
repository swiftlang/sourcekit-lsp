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

final class OnTypeFormattingTests: SourceKitLSPTestCase {
  /// End-to-end smoke test verifying that on-type formatting formats only the target line without altering unselected
  /// lines and reaches a fixed point without assuming specific formatting rules.
  func testOnTypeFormattingIsolatesTargetLineAndIsIdempotent() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let prefix = "func foo() {\n"
    let suffix = "\nlet   unselectedNextLine   =   1\n}\n}"
    let source = "\(prefix)if let x =     bar() 1️⃣{\(suffix)"
    let positions = testClient.openDocument(source, uri: uri)

    let options = FormattingOptions(tabSize: 4, insertSpaces: true)
    let response = try await testClient.send(
      DocumentOnTypeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"],
        ch: "{",
        options: options
      )
    )

    let edits = try XCTUnwrap(response)
    XCTAssertFalse(edits.isEmpty)
    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })

    let (_, unmarkedSource) = extractMarkers(source)
    let formattedSource = apply(edits: edits, to: unmarkedSource)
    XCTAssertTrue(formattedSource.hasPrefix(prefix), "Formatted output altered unselected prefix:\n\(formattedSource)")
    XCTAssertTrue(formattedSource.hasSuffix(suffix), "Formatted output altered unselected suffix:\n\(formattedSource)")

    let formattedLine = String(formattedSource.dropFirst(prefix.count).dropLast(suffix.count))
    XCTAssertEqual(
      formattedLine.filter { !$0.isWhitespace },
      "ifletx=bar(){"
    )

    let secondURI = DocumentURI(for: .swift)
    let secondPositions = testClient.openDocument(
      "\(prefix)\(formattedLine)1️⃣\(suffix)",
      uri: secondURI
    )
    let secondResponse = try await testClient.send(
      DocumentOnTypeFormattingRequest(
        textDocument: TextDocumentIdentifier(secondURI),
        position: secondPositions["1️⃣"],
        ch: "{",
        options: options
      )
    )
    XCTAssertEqual(secondResponse, [])
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
          2️⃣

      }
      }
      """,
      uri: uri
    )

    for marker in ["1️⃣", "2️⃣"] {
      let response = try await testClient.send(
        DocumentOnTypeFormattingRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: positions[marker],
          ch: "\n",
          options: FormattingOptions(tabSize: 2, insertSpaces: true)
        )
      )

      let edits = try XCTUnwrap(response)
      XCTAssertEqual(edits, [])
    }
  }
}
