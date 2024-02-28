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

import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import XCTest

final class PublishDiagnosticsTests: XCTestCase {
  func testUnknownIdentifierDiagnostic() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(
      """
      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let diags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    XCTAssertEqual(
      diags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )
  }

  func testRangeShiftAfterNewlineAdded() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(
      """
      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(
            range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
            rangeLength: 0,
            text: "\n"
          )
        ]
      )
    )

    let editDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )
  }

  func testRangeShiftAfterNewlineRemoved() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(
      """

      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(
            range: Position(line: 0, utf16index: 0)..<Position(line: 1, utf16index: 0),
            rangeLength: 1,
            text: ""
          )
        ]
      )
    )

    let editDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )
  }
}
