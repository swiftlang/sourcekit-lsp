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

import LanguageServerProtocol
import LSPTestSupport
import SKTestSupport
import XCTest

final class DiagnosticsTests: XCTestCase {
  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  override func setUp() {
    connection = TestSourceKitServer()
    sk = connection.client
    let documentCapabilities = TextDocumentClientCapabilities()
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))
  }

  override func tearDown() {
    sk = nil
    connection = nil
  }
  
  private func openDocument(text: String) {
    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(URL(fileURLWithPath: "/DiagnosticsTests/\(UUID()).swift")),
      language: .swift,
      version: 0,
      text: text
    )))
  }

  func testUnknownIdentifierDiagnostic() {
    let syntacticDiagnosticsReceived = self.expectation(description: "Syntactic diagnotistics received")
    let semanticDiagnosticsReceived = self.expectation(description: "Semantic diagnotistics received")

    sk.appendOneShotNotificationHandler  { (note: Notification<PublishDiagnosticsNotification>) in
      // Unresolved identifier is not a syntactic diagnostic.
      XCTAssertEqual(note.params.diagnostics, [])
      syntacticDiagnosticsReceived.fulfill()
    }

    sk.appendOneShotNotificationHandler  { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(note.params.diagnostics.first?.range, Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9))
      semanticDiagnosticsReceived.fulfill()
    }

    openDocument(text: """
    func foo() {
      invalid
    }
    """)

    self.wait(for: [syntacticDiagnosticsReceived, semanticDiagnosticsReceived], timeout: 5)
  }
}
