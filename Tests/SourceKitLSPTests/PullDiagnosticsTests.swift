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

final class PullDiagnosticsTests: XCTestCase {
  func testUnknownIdentifierDiagnostic() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(
      """
      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let report = try await testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))
    guard case .full(let fullReport) = report else {
      XCTFail("Expected full diagnostics report")
      return
    }

    XCTAssertEqual(fullReport.items.count, 1)
    let diagnostic = try XCTUnwrap(fullReport.items.first)
    XCTAssertEqual(diagnostic.range, Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9))
  }

  /// Test that we can get code actions for pulled diagnostics (https://github.com/apple/sourcekit-lsp/issues/776)
  func testCodeActions() async throws {
    let testClient = try await TestSourceKitLSPClient(
      capabilities: ClientCapabilities(
        workspace: nil,
        textDocument: .init(
          codeAction: .init(codeActionLiteralSupport: .init(codeActionKind: .init(valueSet: [.quickFix])))
        )
      )
    )
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(
      """
      protocol MyProtocol {
        func bar()
      }

      struct Test: MyProtocol {}
      """,
      uri: uri
    )
    let report = try await testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))
    guard case .full(let fullReport) = report else {
      XCTFail("Expected full diagnostics report")
      return
    }
    let diagnostics = fullReport.items

    XCTAssertEqual(diagnostics.count, 1)
    let diagnostic = try XCTUnwrap(diagnostics.first)
    XCTAssertEqual(diagnostic.range, Position(line: 4, utf16index: 7)..<Position(line: 4, utf16index: 7))
    let note = try XCTUnwrap(diagnostic.relatedInformation?.first)
    XCTAssertEqual(note.location.range, Position(line: 4, utf16index: 7)..<Position(line: 4, utf16index: 7))
    XCTAssertEqual(note.codeActions?.count ?? 0, 1)

    let response = try await testClient.send(
      CodeActionRequest(
        range: note.location.range,
        context: CodeActionContext(
          diagnostics: diagnostics,
          only: [.quickFix],
          triggerKind: .invoked
        ),
        textDocument: TextDocumentIdentifier(note.location.uri)
      )
    )

    guard case .codeActions(let actions) = response else {
      XCTFail("Expected codeActions response")
      return
    }

    XCTAssertEqual(actions.count, 1)
    let action = try XCTUnwrap(actions.first)
    // Allow the action message to be the one before or after
    // https://github.com/apple/swift/pull/67909, ensuring this test passes with
    // a sourcekitd that contains the change from that PR as well as older
    // toolchains that don't contain the change yet.
    XCTAssert(
      [
        "add stubs for conformance",
        "do you want to add protocol stubs?",
      ].contains(action.title)
    )
  }

  func testNotesFromIntegratedSwiftSyntaxDiagnostics() async throws {
    // Create a workspace that has compile_commands.json so that it has a build system but no compiler arguments
    // for test.swift so that we fall back to producing diagnostics from the built-in swift-syntax.
    let ws = try await MultiFileTestWorkspace(files: [
      "test.swift": "func foo() 1️⃣{2️⃣",
      "compile_commands.json": "[]",
    ])

    let (uri, positions) = try ws.openDocument("test.swift")

    let report = try await ws.testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))
    guard case .full(let fullReport) = report else {
      XCTFail("Expected full diagnostics report")
      return
    }
    XCTAssertEqual(fullReport.items.count, 1)
    let diagnostic = try XCTUnwrap(fullReport.items.first)
    XCTAssertEqual(diagnostic.message, "expected '}' to end function")
    XCTAssertEqual(diagnostic.range, Range(positions["2️⃣"]))

    XCTAssertEqual(diagnostic.relatedInformation?.count, 1)
    let note = try XCTUnwrap(diagnostic.relatedInformation?.first)
    XCTAssertEqual(note.message, "to match this opening '{'")
    XCTAssertEqual(note.location.range, positions["1️⃣"]..<positions["2️⃣"])
  }
}
