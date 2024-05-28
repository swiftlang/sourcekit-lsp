//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import XCTest

/// Tests that test the overall state of the SourceKit-LSP server, that's not really specific to any language
final class LifecycleTests: XCTestCase {
  func testInitLocal() async throws {
    let testClient = try await TestSourceKitLSPClient(initialize: false)

    let initResult = try await testClient.send(
      InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil
      )
    )

    guard case .options(let syncOptions) = initResult.capabilities.textDocumentSync else {
      XCTFail("Unexpected textDocumentSync property")
      return
    }
    XCTAssertEqual(syncOptions.openClose, true)
    XCTAssertNotNil(initResult.capabilities.completionProvider)
  }

  func testCancellation() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      class Foo {
        func slow(x: Invalid1, y: Invalid2) {
        1️⃣  x / y / x / y / x / y / x / y . 2️⃣
        }

        struct Foo {
          let 3️⃣fooMember: String
        }

        func fast(a: Foo) {
          a.4️⃣
        }
      }
      """,
      uri: uri
    )

    let completionRequestReplied = self.expectation(description: "completion request replied")

    let requestID = RequestID.string("cancellation-test")
    testClient.server.handle(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"]),
      id: requestID
    ) { reply in
      switch reply {
      case .success:
        XCTFail("Expected completion request to fail because it was cancelled")
      case .failure(let error):
        XCTAssertEqual(error, ResponseError.cancelled)
      }
      completionRequestReplied.fulfill()
    }
    testClient.send(CancelRequestNotification(id: requestID))

    try await fulfillmentOfOrThrow([completionRequestReplied])

    let fastStartDate = Date()
    let fastReply = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["4️⃣"])
    )
    XCTAssert(!fastReply.items.isEmpty)
    XCTAssertLessThan(Date().timeIntervalSince(fastStartDate), 2, "Fast request wasn't actually fast")

    // Remove the slow-to-typecheck line. This causes the implicit diagnostics request for the push diagnostics
    // notification to get cancelled, which unblocks sourcekitd for later tests.
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: positions["1️⃣"]..<positions["2️⃣"], text: "")
        ]
      )
    )

    let cursorInfoStartDate = Date()
    // Check that semantic functionality based on the AST is working again.
    let symbolInfo = try await testClient.send(
      SymbolInfoRequest(textDocument: TextDocumentIdentifier(uri), position: positions["3️⃣"])
    )
    XCTAssertLessThan(
      Date().timeIntervalSince(cursorInfoStartDate),
      2,
      "Cursor info request wasn't fast. sourcekitd still blocked?"
    )
    XCTAssertGreaterThan(symbolInfo.count, 0)
  }
}
