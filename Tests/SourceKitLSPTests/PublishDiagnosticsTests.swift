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
  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  private var uri: DocumentURI!
  private var textDocument: TextDocumentIdentifier { TextDocumentIdentifier(uri) }
  private var version: Int!

  override func setUp() {
    version = 0
    uri = DocumentURI(URL(fileURLWithPath: "/PublishDiagnosticsTests/\(UUID()).swift"))
    connection = TestSourceKitServer()
    let documentCapabilities = TextDocumentClientCapabilities()
    awaitTask(description: "Initialized") {
      _ = try await self.connection.send(
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
  }

  override func tearDown() {
    connection = nil
  }

  private func openDocument(text: String) {
    connection.send(
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
    connection.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(
          uri,
          version: version
        ),
        contentChanges: changes
      )
    )
  }

  func testUnknownIdentifierDiagnostic() async throws {
    openDocument(
      text: """
        func foo() {
          invalid
        }
        """
    )

    let syntacticDiags = try await connection.nextDiagnosticsNotification()
    // Unresolved identifier is not a syntactic diagnostic.
    XCTAssertEqual(syntacticDiags.diagnostics, [])

    let semanticDiags = try await connection.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      semanticDiags.diagnostics.first?.range,
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

    let openSyntacticDiags = try await connection.nextDiagnosticsNotification()
    // Unresolved identifier is not a syntactic diagnostic.
    XCTAssertEqual(openSyntacticDiags.diagnostics, [])

    let openSemanticDiags = try await connection.nextDiagnosticsNotification()
    XCTAssertEqual(openSemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openSemanticDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )

    editDocument(changes: [
      TextDocumentContentChangeEvent(
        range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
        rangeLength: 0,
        text: "\n"
      )
    ])

    let editSyntacticDiags = try await connection.nextDiagnosticsNotification()
    // We should report the semantic diagnostic reported by the edit range-shifted
    XCTAssertEqual(editSyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editSyntacticDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )

    let editSemanticDiags = try await connection.nextDiagnosticsNotification()
    XCTAssertEqual(editSemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editSemanticDiags.diagnostics.first?.range,
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

    let openSyntacticDiags = try await connection.nextDiagnosticsNotification()
    // Unresolved identifier is not a syntactic diagnostic.
    XCTAssertEqual(openSyntacticDiags.diagnostics, [])

    let openSemanticDiags = try await connection.nextDiagnosticsNotification()
    XCTAssertEqual(openSemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openSemanticDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )

    editDocument(changes: [
      TextDocumentContentChangeEvent(
        range: Position(line: 0, utf16index: 0)..<Position(line: 1, utf16index: 0),
        rangeLength: 1,
        text: ""
      )
    ])

    let editSyntacticDiags = try await connection.nextDiagnosticsNotification()
    // We should report the semantic diagnostic reported by the edit range-shifted
    XCTAssertEqual(editSyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editSyntacticDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )

    let editSemanticDiags = try await connection.nextDiagnosticsNotification()
    XCTAssertEqual(editSemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editSemanticDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )
  }
}
