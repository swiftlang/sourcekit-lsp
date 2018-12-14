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
import SKSupport
import SKTestSupport
import XCTest

@testable import SourceKit

final class FoldingRangeTests: XCTestCase {

  typealias FoldingRangeCapabilities = TextDocumentClientCapabilities.FoldingRange

  /// Base document text to use for folding range tests.
  let text: String = """
    /// DC1
    /// - Returns: DC1

    /**
      DC2

      - Parameter param: DC2

      - Throws: DC2
      DC2
      DC2

      - Returns: DC2
    */
    struct S {
      //c1
      //c2
      /*
       c3
      */
      var abc: Int

      func test(a: Int) {
        guard a > 0 else { return }
        self.abc = a
      }
      /* c4 */
    }
    """

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  var workspace: Workspace! = nil

  override func tearDown() {
    workspace = nil
    sk = nil
    connection = nil
  }

  func initialize(capabilities: FoldingRangeCapabilities) {
    connection = TestSourceKitServer()
    sk = connection.client
    var documentCapabilities = TextDocumentClientCapabilities()
    documentCapabilities.foldingRange = capabilities
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURL: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))

    workspace = connection.server!.workspace!
  }

  func getFoldingRangeRequest(text: String? = nil) -> FoldingRangeRequest {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true

    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text:
      text ?? self.text)))

    return FoldingRangeRequest(textDocument: TextDocumentIdentifier(url))
  }

  func testPartialLineFolding() {
    var capabilities = FoldingRangeCapabilities()
    capabilities.lineFoldingOnly = false
    initialize(capabilities: capabilities)

    let request = getFoldingRangeRequest()
    let ranges = try! sk.sendSync(request)!

    XCTAssertEqual(ranges, [
      FoldingRange(startLine: 0, startUTF16Index: 0, endLine: 2, endUTF16Index: 0, kind: .comment),
      FoldingRange(startLine: 3, startUTF16Index: 0, endLine: 13, endUTF16Index: 2, kind: .comment),
      FoldingRange(startLine: 15, startUTF16Index: 2, endLine: 16, endUTF16Index: 0, kind: .comment),
      FoldingRange(startLine: 16, startUTF16Index: 2, endLine: 17, endUTF16Index: 0, kind: .comment),
      FoldingRange(startLine: 17, startUTF16Index: 2, endLine: 19, endUTF16Index: 4, kind: .comment),
      FoldingRange(startLine: 26, startUTF16Index: 2, endLine: 26, endUTF16Index: 10, kind: .comment),
      FoldingRange(startLine: 14, startUTF16Index: 10, endLine: 27, endUTF16Index: 0, kind: nil),
      FoldingRange(startLine: 22, startUTF16Index: 21, endLine: 25, endUTF16Index: 2, kind: nil),
      FoldingRange(startLine: 23, startUTF16Index: 22, endLine: 23, endUTF16Index: 30, kind: nil),
    ])
  }

  func testLineFoldingOnly() {
    var capabilities = FoldingRangeCapabilities()
    capabilities.lineFoldingOnly = true
    initialize(capabilities: capabilities)

    let request = getFoldingRangeRequest()
    let ranges = try! sk.sendSync(request)!

    XCTAssertEqual(ranges, [
      FoldingRange(startLine: 0, endLine: 1, kind: .comment),
      FoldingRange(startLine: 3, endLine: 12, kind: .comment),
      FoldingRange(startLine: 17, endLine: 18, kind: .comment),
      FoldingRange(startLine: 14, endLine: 26, kind: nil),
      FoldingRange(startLine: 22, endLine: 24, kind: nil),
    ])
  }

  func testRangeLimit() {
    var capabilities = FoldingRangeCapabilities()
    capabilities.lineFoldingOnly = false

    capabilities.rangeLimit = -100
    initialize(capabilities: capabilities)
    XCTAssertEqual(try! sk.sendSync(getFoldingRangeRequest())!.count, 0)

    capabilities.rangeLimit = 0
    initialize(capabilities: capabilities)
    XCTAssertEqual(try! sk.sendSync(getFoldingRangeRequest())!.count, 0)

    capabilities.rangeLimit = 4
    initialize(capabilities: capabilities)
    XCTAssertEqual(try! sk.sendSync(getFoldingRangeRequest())!.count, 4)

    capabilities.rangeLimit = 5000
    initialize(capabilities: capabilities)
    XCTAssertEqual(try! sk.sendSync(getFoldingRangeRequest())!.count, 9)

    capabilities.rangeLimit = nil
    initialize(capabilities: capabilities)
    XCTAssertEqual(try! sk.sendSync(getFoldingRangeRequest())!.count, 9)
  }

  func testEmptyText() {
    let capabilities = FoldingRangeCapabilities()
    initialize(capabilities: capabilities)

    let request = getFoldingRangeRequest(text: "")
    let ranges = try! sk.sendSync(request)!

    XCTAssertEqual(ranges.count, 0)
  }
}
