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
  /// The mock client used to communicate with the SourceKit-LSP server.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var testClient: TestSourceKitLSPClient! = nil

  /// The URI of the document that is being tested by the current test case.
  ///
  /// - Note: This URI is set to a unique value before each test case in `setUp`.
  private var uri: DocumentURI!

  /// The current verion of the document being opened.
  ///
  /// - Note: This gets reset to 0 in `setUp` and incremented on every call to
  ///   `openDocument` and `editDocument`.
  private var version: Int!

  override func setUp() async throws {
    version = 0
    uri = DocumentURI(URL(fileURLWithPath: "/PublishDiagnosticsTests/\(UUID()).swift"))
    testClient = TestSourceKitLSPClient()
    let documentCapabilities = TextDocumentClientCapabilities()
    _ = try await self.testClient.send(
      InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
        trace: .off,
        workspaceFolders: nil
      )
    )
  }

  override func tearDown() {
    testClient = nil
  }

  // MARK: - Helpers

  private func openDocument(text: String) {
    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: version,
          text: text
        )
      )
    )
    version += 1
  }

  private func editDocument(changes: [TextDocumentContentChangeEvent]) {
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(
          uri,
          version: version
        ),
        contentChanges: changes
      )
    )
    version += 1
  }

  // MARK: - Tests

  func testUnknownIdentifierDiagnostic() async throws {
    openDocument(
      text: """
        func foo() {
          invalid
        }
        """
    )

    let diags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    XCTAssertEqual(
      diags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )
  }

  func testRangeShiftAfterNewlineAdded() async throws {
    openDocument(
      text: """
        func foo() {
          invalid
        }
        """
    )

    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )

    editDocument(changes: [
      TextDocumentContentChangeEvent(
        range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
        rangeLength: 0,
        text: "\n"
      )
    ])

    let editDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )
  }

  func testRangeShiftAfterNewlineRemoved() async throws {
    openDocument(
      text: """

        func foo() {
          invalid
        }
        """
    )

    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )

    editDocument(changes: [
      TextDocumentContentChangeEvent(
        range: Position(line: 0, utf16index: 0)..<Position(line: 1, utf16index: 0),
        rangeLength: 1,
        text: ""
      )
    ])

    let editDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )
  }
}
