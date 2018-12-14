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

    XCTAssertEqual(ranges.count, 9)

    let dc1Range = ranges[0]
    XCTAssertEqual(dc1Range.startLine, 0)
    XCTAssertEqual(dc1Range.endLine, 2)
    XCTAssertEqual(dc1Range.startUTF16Index, 0)
    XCTAssertEqual(dc1Range.endUTF16Index, 0)
    XCTAssertEqual(dc1Range.kind, .comment)

    let dc2Range = ranges[1]
    XCTAssertEqual(dc2Range.startLine, 3)
    XCTAssertEqual(dc2Range.endLine, 13)
    XCTAssertEqual(dc2Range.startUTF16Index, 0)
    XCTAssertEqual(dc2Range.endUTF16Index, 2)
    XCTAssertEqual(dc2Range.kind, .comment)

    let c1Range = ranges[2]
    XCTAssertEqual(c1Range.startLine, 15)
    XCTAssertEqual(c1Range.endLine, 16)
    XCTAssertEqual(c1Range.startUTF16Index, 2)
    XCTAssertEqual(c1Range.endUTF16Index, 0)
    XCTAssertEqual(c1Range.kind, .comment)

    let c2Range = ranges[3]
    XCTAssertEqual(c2Range.startLine, 16)
    XCTAssertEqual(c2Range.endLine, 17)
    XCTAssertEqual(c2Range.startUTF16Index, 2)
    XCTAssertEqual(c2Range.endUTF16Index, 0)
    XCTAssertEqual(c2Range.kind, .comment)

    let c3Range = ranges[4]
    XCTAssertEqual(c3Range.startLine, 17)
    XCTAssertEqual(c3Range.endLine, 19)
    XCTAssertEqual(c3Range.startUTF16Index, 2)
    XCTAssertEqual(c3Range.endUTF16Index, 4)
    XCTAssertEqual(c3Range.kind, .comment)

    let c4Range = ranges[5]
    XCTAssertEqual(c4Range.startLine, 26)
    XCTAssertEqual(c4Range.endLine, 26)
    XCTAssertEqual(c4Range.startUTF16Index, 2)
    XCTAssertEqual(c4Range.endUTF16Index, 10)
    XCTAssertEqual(c4Range.kind, .comment)

    let structRange = ranges[6]
    XCTAssertEqual(structRange.startLine, 14)
    XCTAssertEqual(structRange.endLine, 27)
    XCTAssertEqual(structRange.startUTF16Index, 10)
    XCTAssertEqual(structRange.endUTF16Index, 0)
    XCTAssertNil(structRange.kind)

    let methodRange = ranges[7]
    XCTAssertEqual(methodRange.startLine, 22)
    XCTAssertEqual(methodRange.endLine, 25)
    XCTAssertEqual(methodRange.startUTF16Index, 21)
    XCTAssertEqual(methodRange.endUTF16Index, 2)
    XCTAssertNil(methodRange.kind)

    let guardRange = ranges[8]
    XCTAssertEqual(guardRange.startLine, 23)
    XCTAssertEqual(guardRange.endLine, 23)
    XCTAssertEqual(guardRange.startUTF16Index, 22)
    XCTAssertEqual(guardRange.endUTF16Index, 30)
    XCTAssertNil(guardRange.kind)
  }

  func testLineFoldingOnly() {
    var capabilities = FoldingRangeCapabilities()
    capabilities.lineFoldingOnly = true
    initialize(capabilities: capabilities)

    let request = getFoldingRangeRequest()
    let ranges = try! sk.sendSync(request)!

    XCTAssertEqual(ranges.count, 5)

    let dc1Range = ranges[0]
    XCTAssertEqual(dc1Range.startLine, 0)
    XCTAssertEqual(dc1Range.endLine, 1)
    XCTAssertEqual(dc1Range.kind, .comment)

    let dc2Range = ranges[1]
    XCTAssertEqual(dc2Range.startLine, 3)
    XCTAssertEqual(dc2Range.endLine, 12)
    XCTAssertEqual(dc2Range.kind, .comment)

    let c3Range = ranges[2]
    XCTAssertEqual(c3Range.startLine, 17)
    XCTAssertEqual(c3Range.endLine, 18)
    XCTAssertEqual(c3Range.kind, .comment)

    let structRange = ranges[3]
    XCTAssertEqual(structRange.startLine, 14)
    XCTAssertEqual(structRange.endLine, 26)
    XCTAssertNil(structRange.kind)

    let methodRange = ranges[4]
    XCTAssertEqual(methodRange.startLine, 22)
    XCTAssertEqual(methodRange.endLine, 24)
    XCTAssertNil(methodRange.kind)
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
