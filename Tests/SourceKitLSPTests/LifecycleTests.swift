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
import LanguageServerProtocolExtensions
import SKOptions
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

  func testEmptySourceKitLSPOptionsCanBeDecoded() {
    // Check that none of the keys in `SourceKitLSPOptions` are required.
    XCTAssertEqual(
      try JSONDecoder().decode(SourceKitLSPOptions.self, from: XCTUnwrap("{}".data(using: .utf8))),
      SourceKitLSPOptions(swiftPM: nil, fallbackBuildSystem: nil, compilationDatabase: nil, index: nil, logging: nil)
    )
  }

  func testCancellation() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct A: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }
      struct B: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }
      struct C: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }

      func + (lhs: A, rhs: B) -> A { fatalError() }
      func + (lhs: B, rhs: C) -> A { fatalError() }
      func + (lhs: C, rhs: A) -> A { fatalError() }

      func + (lhs: B, rhs: A) -> B { fatalError() }
      func + (lhs: C, rhs: B) -> B { fatalError() }
      func + (lhs: A, rhs: C) -> B { fatalError() }

      func + (lhs: C, rhs: B) -> C { fatalError() }
      func + (lhs: B, rhs: C) -> C { fatalError() }
      func + (lhs: A, rhs: A) -> C { fatalError() }


      class Foo {
        func slow(x: Invalid1, y: Invalid2) {
        1️⃣  let x: C = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 2️⃣
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

  func testEditWithOutOfRangeLine() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    testClient.openDocument("", uri: uri)

    // Check that we don't crash.
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(Position(line: 2, utf16index: 0)), text: "new")]
      )
    )
  }

  func testEditWithOutOfRangeColumn() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    testClient.openDocument("", uri: uri)

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(Position(line: 0, utf16index: 4)), text: "new")]
      )
    )
  }

  func testOpenFileWithoutPath() async throws {
    let testClient = try await TestSourceKitLSPClient()
    testClient.openDocument("", uri: DocumentURI(try XCTUnwrap(URL(string: "file://"))), language: .swift)
  }
}
