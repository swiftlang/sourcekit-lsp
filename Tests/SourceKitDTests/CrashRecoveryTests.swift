//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ISDBTestSupport
import LSPLogging
import LSPTestSupport
import LanguageServerProtocol
import SKSupport
import SKTestSupport
import SourceKitD
import SourceKitLSP
import XCTest

import enum PackageLoading.Platform

fileprivate extension HoverResponse {
  func contains(string: String) -> Bool {
    switch self.contents {
    case .markedStrings(let markedStrings):
      for markedString in markedStrings {
        switch markedString {
        case .markdown(value: let value), .codeBlock(language: _, value: let value):
          if value.contains(string) {
            return true
          }
        }
      }
    case .markupContent(let markdownString):
      if markdownString.value.contains(string) {
        return true
      }
    }
    return false
  }
}

final class CrashRecoveryTests: XCTestCase {
  func testSourcekitdCrashRecovery() async throws {
    try XCTSkipUnless(Platform.current == .darwin, "Linux and Windows use in-process sourcekitd")
    try XCTSkipIf(longTestsDisabled)

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument("""
      func 1️⃣foo() {
        print("Hello world")
      }
      """, uri: uri)

    // Wait for diagnostics to be produced to make sure the document open got handled by sourcekitd.
    _ = try await testClient.nextDiagnosticsNotification()

    // Do a sanity check and verify that we get the expected result from a hover response before crashing sourcekitd.

    let hoverRequest = HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    let preCrashHoverResponse = try await testClient.send(hoverRequest)
    precondition(
      preCrashHoverResponse?.contains(string: "foo()") ?? false,
      "Sanity check failed. The Hover response did not contain foo(), even before crashing sourcekitd. Received response: \(String(describing: preCrashHoverResponse))"
    )

    // Crash sourcekitd

    let sourcekitdServer =
      await testClient.server._languageService(
        for: uri,
        .swift,
        in: testClient.server.workspaceForDocument(uri: uri)!
      ) as! SwiftLanguageServer

    let sourcekitdCrashed = expectation(description: "sourcekitd has crashed")
    let sourcekitdRestarted = expectation(description: "sourcekitd has been restarted (syntactic only)")
    let semanticFunctionalityRestored = expectation(
      description: "sourcekitd has restored semantic language functionality"
    )

    await sourcekitdServer.addStateChangeHandler { (oldState, newState) in
      switch newState {
      case .connectionInterrupted:
        sourcekitdCrashed.fulfill()
      case .semanticFunctionalityDisabled:
        sourcekitdRestarted.fulfill()
      case .connected:
        semanticFunctionalityRestored.fulfill()
      }
    }

    await sourcekitdServer._crash()

    try await fulfillmentOfOrThrow([sourcekitdCrashed], timeout: 5)
    try await fulfillmentOfOrThrow([sourcekitdRestarted], timeout: 30)

    // sourcekitd's semantic request timer is only started when the first semantic request comes in.
    // Send a hover request (which will fail) to trigger that timer.
    // Afterwards wait for semantic functionality to be restored.
    _ = try? await testClient.send(hoverRequest)
    try await fulfillmentOfOrThrow([semanticFunctionalityRestored], timeout: 30)

    // Check that we get the same hover response from the restored in-memory state

    await assertNoThrow {
      let postCrashHoverResponse = try await testClient.send(hoverRequest)
      XCTAssertTrue(postCrashHoverResponse?.contains(string: "foo()") ?? false)
    }
  }

  private func crashClangd(for testClient: TestSourceKitLSPClient, document docUri: DocumentURI) async throws {
    let clangdServer = await testClient.server._languageService(
      for: docUri,
      .cpp,
      in: testClient.server.workspaceForDocument(uri: docUri)!
    )!

    let clangdCrashed = self.expectation(description: "clangd crashed")
    let clangdRestarted = self.expectation(description: "clangd restarted")

    await clangdServer.addStateChangeHandler { (oldState, newState) in
      switch newState {
      case .connectionInterrupted:
        clangdCrashed.fulfill()
      case .connected:
        clangdRestarted.fulfill()
      default:
        break
      }
    }

    await clangdServer._crash()

    try await fulfillmentOfOrThrow([clangdCrashed])
    try await fulfillmentOfOrThrow([clangdRestarted])
  }

  func testClangdCrashRecovery() async throws {
    try XCTSkipIf(longTestsDisabled)

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.cpp)

    let positions = testClient.openDocument("1️⃣", uri: uri)

    // Make a change to the file that's not saved to disk. This way we can check that we re-open the correct in-memory state.

    let addFuncChange = TextDocumentContentChangeEvent(
      range: Range(positions["1️⃣"]),
      rangeLength: 0,
      text: """

        void main() {
        }
        """
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [addFuncChange]
      )
    )

    // Do a sanity check and verify that we get the expected result from a hover response before crashing clangd.

    let expectedHoverRange = Position(line: 1, utf16index: 5)..<Position(line: 1, utf16index: 9)

    let hoverRequest = HoverRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: Position(line: 1, utf16index: 6)
    )
    let preCrashHoverResponse = try await testClient.send(hoverRequest)
    precondition(
      preCrashHoverResponse?.range == expectedHoverRange,
      "Sanity check failed. The Hover response was not what we expected, even before crashing sourcekitd"
    )

    // Crash clangd

    try await crashClangd(for: testClient, document: uri)

    // Check that we have re-opened the document with the correct in-memory state

    await assertNoThrow {
      let postCrashHoverResponse = try await testClient.send(hoverRequest)
      XCTAssertEqual(postCrashHoverResponse?.range, expectedHoverRange)
    }
  }

  func testClangdCrashRecoveryReopensWithCorrectBuildSettings() async throws {
    try XCTSkipIf(longTestsDisabled)

    let ws = try await MultiFileTestWorkspace(files: [
      "main.cpp": """
      #if FOO
      void 1️⃣foo2️⃣() {}
      #else
      void foo() {}
      #endif

      int main() {
        3️⃣foo4️⃣();
      }
      """,
      "compile_flags.txt": """
      -DFOO
      """,
    ])

    let (mainUri, positions) = try ws.openDocument("main.cpp")

    // Do a sanity check and verify that we get the expected result from a hover response before crashing clangd.

    let expectedHighlightResponse = [
      DocumentHighlight(range: positions["1️⃣"]..<positions["2️⃣"], kind: .text),
      DocumentHighlight(range: positions["3️⃣"]..<positions["4️⃣"], kind: .text),
    ]

    let highlightRequest = DocumentHighlightRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["3️⃣"]
    )
    let preCrashHighlightResponse = try await ws.testClient.send(highlightRequest)
    precondition(
      preCrashHighlightResponse == expectedHighlightResponse,
      "Sanity check failed. The Hover response was not what we expected, even before crashing sourcekitd"
    )

    // Crash clangd

    try await crashClangd(for: ws.testClient, document: mainUri)

    // Check that we have re-opened the document with the correct build settings
    // If we did not recover the correct build settings, document highlight would
    // pick the definition of foo() in the #else branch.

    await assertNoThrow {
      let postCrashHighlightResponse = try await ws.testClient.send(highlightRequest)
      XCTAssertEqual(postCrashHighlightResponse, expectedHighlightResponse)
    }
  }

  func testPreventClangdCrashLoop() async throws {
    try XCTSkipIf(longTestsDisabled)

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.cpp)

    let positions = testClient.openDocument("1️⃣", uri: uri)

    // Send a nonsensical request to wait for clangd to start up

    let hoverRequest = HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    _ = try await testClient.send(hoverRequest)

    // Keep track of clangd crashes

    let clangdServer = await testClient.server._languageService(
      for: uri,
      .cpp,
      in: testClient.server.workspaceForDocument(uri: uri)!
    )!

    let clangdCrashed = self.expectation(description: "clangd crashed")
    clangdCrashed.assertForOverFulfill = false

    let clangdRestartedFirstTime = self.expectation(description: "clangd restarted for the first time")
    let clangdRestartedSecondTime = self.expectation(description: "clangd restarted for the second time")

    var clangdHasRestartedFirstTime = false

    await clangdServer.addStateChangeHandler { (oldState, newState) in
      switch newState {
      case .connectionInterrupted:
        clangdCrashed.fulfill()
      case .connected:
        if !clangdHasRestartedFirstTime {
          clangdRestartedFirstTime.fulfill()
          clangdHasRestartedFirstTime = true
        } else {
          clangdRestartedSecondTime.fulfill()
        }
      default:
        break
      }
    }

    await clangdServer._crash()

    try await fulfillmentOfOrThrow([clangdCrashed], timeout: 5)
    try await fulfillmentOfOrThrow([clangdRestartedFirstTime], timeout: 30)
    // Clangd has restarted. Note the date so we can check that the second restart doesn't happen too quickly.
    let firstRestartDate = Date()

    // Crash clangd again. This time, it should only restart after a delay.
    await clangdServer._crash()

    try await fulfillmentOfOrThrow([clangdRestartedSecondTime], timeout: 30)
    XCTAssert(
      Date().timeIntervalSince(firstRestartDate) > 5,
      "Clangd restarted too quickly after crashing twice in a row. We are not preventing crash loops."
    )
  }
}
