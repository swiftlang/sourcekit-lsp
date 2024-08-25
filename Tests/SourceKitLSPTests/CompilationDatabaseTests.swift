//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildSystemIntegration
import Foundation
import LanguageServerProtocol
import SKTestSupport
import TSCBasic
import XCTest

final class CompilationDatabaseTests: XCTestCase {
  func testModifyCompilationDatabase() async throws {
    let project = try await MultiFileTestProject(files: [
      "main.cpp": """
      #if FOO
      void 1️⃣foo2️⃣() {}
      #else
      void 3️⃣foo4️⃣() {}
      #endif

      int main() {
        5️⃣foo6️⃣();
      }
      """,
      "compile_flags.txt": """
      -DFOO
      """,
    ])

    let (mainUri, positions) = try project.openDocument("main.cpp")

    // Do a sanity check and verify that we get the expected result from a hover response before modifying the compile commands.

    let highlightRequest = DocumentHighlightRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["5️⃣"]
    )
    let preChangeHighlightResponse = try await project.testClient.send(highlightRequest)
    XCTAssertEqual(
      preChangeHighlightResponse,
      [
        DocumentHighlight(range: positions["1️⃣"]..<positions["2️⃣"], kind: .text),
        DocumentHighlight(range: positions["5️⃣"]..<positions["6️⃣"], kind: .text),
      ]
    )

    // Remove -DFOO from the compile commands.

    let compileFlagsUri = try project.uri(for: "compile_flags.txt")
    try "".write(to: compileFlagsUri.fileURL!, atomically: false, encoding: .utf8)

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: compileFlagsUri, type: .changed)
      ])
    )

    // Ensure that the DidChangeWatchedFilesNotification is handled before we continue.
    try await project.testClient.send(PollIndexRequest())

    // DocumentHighlight should now point to the definition in the `#else` block.

    let expectedPostEditHighlight = [
      DocumentHighlight(range: positions["3️⃣"]..<positions["4️⃣"], kind: .text),
      DocumentHighlight(range: positions["5️⃣"]..<positions["6️⃣"], kind: .text),
    ]

    var didReceiveCorrectHighlight = false

    // Updating the build settings takes a few seconds.
    // Send highlight requests every second until we receive correct results.
    for _ in 0..<30 {
      let postChangeHighlightResponse = try await project.testClient.send(highlightRequest)

      if postChangeHighlightResponse == expectedPostEditHighlight {
        didReceiveCorrectHighlight = true
        break
      }
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    XCTAssert(didReceiveCorrectHighlight)
  }
}
