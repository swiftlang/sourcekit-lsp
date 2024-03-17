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
final class ReferencesTests: XCTestCase {
  func testReferencesInMacro() async throws {
    let ws = try await IndexedSingleSwiftFileTestProject(
      """
      import Observation

      @available(macOS 14.0, *)
      1️⃣@Observable
      class 2️⃣Foo {
        var x: Int = 2
      }
      """
    )

    let response = try await ws.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(ws.fileURI),
        position: ws.positions["2️⃣"],
        context: ReferencesContext(includeDeclaration: true)
      )
    )
    XCTAssertEqual(
      response,
      [
        Location(uri: ws.fileURI, range: Range(ws.positions["1️⃣"])),
        Location(uri: ws.fileURI, range: Range(ws.positions["2️⃣"])),
      ]
    )
  }
}
