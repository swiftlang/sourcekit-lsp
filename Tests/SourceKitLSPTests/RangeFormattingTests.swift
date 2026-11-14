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
import SKUtilities
import SourceKitLSP
import SwiftLanguageService
import XCTest

final class RangeFormattingTests: SourceKitLSPTestCase {
  func testSingleLineAndMultiLineOffsetArguments() throws {
    let marked = """
      1️⃣func foo() {
      if let x = bar() {
      2️⃣// do stuff3️⃣
      }
      }4️⃣
      """
    let (positions, unmarked) = DocumentPositions.extract(from: marked)
    let snapshot = DocumentSnapshot(
      uri: DocumentURI(for: .swift),
      language: .swift,
      version: 0,
      lineTable: LineTable(unmarked),
      origin: .openDocument
    )
    let options = FormattingOptions(tabSize: 2, insertSpaces: true)

    let singleLineArgs = try swiftFormatArguments(
      snapshot: snapshot,
      textDocument: TextDocumentIdentifier(snapshot.uri),
      options: options,
      range: positions["2️⃣"]..<positions["3️⃣"]
    )
    XCTAssertEqual(Array(singleLineArgs.suffix(2)), ["--offsets", "32:42"])

    let multiLineArgs = try swiftFormatArguments(
      snapshot: snapshot,
      textDocument: TextDocumentIdentifier(snapshot.uri),
      options: options,
      range: positions["1️⃣"]..<positions["4️⃣"]
    )
    XCTAssertEqual(Array(multiLineArgs.suffix(2)), ["--offsets", "0:\(unmarked.utf8.count - 1)"])
  }

  func testColumnAndEmptyRangeOffsetArguments() throws {
    let marked = "let 🎉 1️⃣=     2️⃣bar()\n"
    let (positions, unmarked) = DocumentPositions.extract(from: marked)
    let snapshot = DocumentSnapshot(
      uri: DocumentURI(for: .swift),
      language: .swift,
      version: 0,
      lineTable: LineTable(unmarked),
      origin: .openDocument
    )
    let options = FormattingOptions(tabSize: 2, insertSpaces: true)
    let start = positions["1️⃣"]
    let end = positions["2️⃣"]

    // "let 🎉 " is 9 UTF-8 bytes ("let " = 4, "🎉" = 4, " " = 1), "=     " is 6 bytes (offsets 9...14).
    let columnArgs = try swiftFormatArguments(
      snapshot: snapshot,
      textDocument: TextDocumentIdentifier(snapshot.uri),
      options: options,
      range: start..<end
    )
    XCTAssertEqual(Array(columnArgs.suffix(2)), ["--offsets", "9:14"])

    // An empty LSP range clamps the inclusive upper bound to `lowerBound`.
    let emptyArgs = try swiftFormatArguments(
      snapshot: snapshot,
      textDocument: TextDocumentIdentifier(snapshot.uri),
      options: options,
      range: start..<start
    )
    XCTAssertEqual(Array(emptyArgs.suffix(2)), ["--offsets", "9:9"])
  }

  /// End-to-end smoke test verifying that range formatting passes `--offsets` to `swift-format`, leaves unselected
  /// surrounding lines untouched, and reaches a fixed point without assuming specific formatting rules.
  func testRangeFormattingIsolatesSelectedLineAndIsIdempotent() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let prefix = "let   unselectedBefore   =   1\n"
    let suffix = "\nlet   unselectedAfter   =   3"
    let source = "\(prefix)1️⃣let   selectedLine   =   22️⃣\(suffix)"
    let positions = testClient.openDocument(source, uri: uri)

    let options = FormattingOptions(tabSize: 2, insertSpaces: true)
    let response = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        range: positions["1️⃣"]..<positions["2️⃣"],
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

    let formattedMiddle = String(formattedSource.dropFirst(prefix.count).dropLast(suffix.count))
    XCTAssertEqual(
      formattedMiddle.filter { !$0.isWhitespace },
      "letselectedLine=2"
    )

    let secondURI = DocumentURI(for: .swift)
    let secondPositions = testClient.openDocument(
      "\(prefix)1️⃣\(formattedMiddle)2️⃣\(suffix)",
      uri: secondURI
    )
    let secondResponse = try await testClient.send(
      DocumentRangeFormattingRequest(
        textDocument: TextDocumentIdentifier(secondURI),
        range: secondPositions["1️⃣"]..<secondPositions["2️⃣"],
        options: options
      )
    )
    XCTAssertEqual(secondResponse, [])
  }
}
