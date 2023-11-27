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

import LanguageServerProtocol
import SKTestSupport
import XCTest

class DefinitionTests: XCTestCase {
  func testJumpToDefinitionAtEndOfIdentifier() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      let 1️⃣foo = 1
      _ = foo2️⃣
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(locations, [Location(uri: uri, range: Range(positions["1️⃣"]))])
  }
}
