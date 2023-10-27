//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import SKTestSupport
import XCTest

final class SwiftPMIntegrationTests: XCTestCase {

  func testSwiftPMIntegration() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "Lib.swift": """
        struct Lib {
          func 1️⃣foo() {}
        }
        """,
        "Other.swift": """
        func test() {
          Lib().2️⃣foo()
        }
        """,
      ],
      build: true
    )

    let (otherUri, otherPositions) = try ws.openDocument("Other.swift")
    let callPosition = otherPositions["2️⃣"]

    let refs = try await ws.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(otherUri),
        position: callPosition,
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    XCTAssertEqual(
      Set(refs),
      [
        Location(uri: otherUri, range: Range(callPosition)),
        Location(uri: try ws.uri(for: "Lib.swift"), range: Range(try ws.position(of: "1️⃣", in: "Lib.swift"))),
      ]
    )

    let completions = try await ws.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(otherUri), position: callPosition)
    )

    XCTAssertEqual(
      completions.items,
      [
        CompletionItem(
          label: "foo()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          sortText: nil,
          filterText: "foo()",
          insertText: "foo()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(callPosition), newText: "foo()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Lib",
          deprecated: false,
          sortText: nil,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(callPosition), newText: "self")
          )
        ),
      ]
    )
  }

  func testAddFile() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "Lib.swift": """
        struct Lib {
          func foo() {
            1️⃣
          }
        }
        """
      ],
      build: true
    )

    let newFileUrl = ws.scratchDirectory
      .appendingPathComponent("Sources")
      .appendingPathComponent("MyLibrary")
      .appendingPathComponent("Other.swift")
    let newFileUri = DocumentURI(newFileUrl)

    let newFileContents = """
      func baz(l: Lib)  {
        l.2️⃣foo()
      }
      """
    try extractMarkers(newFileContents).textWithoutMarkers.write(to: newFileUrl, atomically: false, encoding: .utf8)

    // Check that we don't get cross-file code completion before we send a `DidChangeWatchedFilesNotification` to make
    // sure we didn't include the file in the initial retrieval of build settings.
    let (oldFileUri, oldFilePositions) = try ws.openDocument("Lib.swift")
    let newFilePositions = ws.testClient.openDocument(newFileContents, uri: newFileUri)

    let completionsBeforeDidChangeNotification = try await ws.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(newFileUri), position: newFilePositions["2️⃣"])
    )
    XCTAssertEqual(completionsBeforeDidChangeNotification.items, [])

    // Send a `DidChangeWatchedFilesNotification` and verify that we now get cross-file code completion.
    ws.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: newFileUri, type: .created)
      ])
    )

    // Ensure that the DidChangeWatchedFilesNotification is handled before we continue.
    _ = try await ws.testClient.send(BarrierRequest())

    let completions = try await ws.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(newFileUri), position: newFilePositions["2️⃣"])
    )

    XCTAssertEqual(
      completions.items,
      [
        CompletionItem(
          label: "foo()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          sortText: nil,
          filterText: "foo()",
          insertText: "foo()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(newFilePositions["2️⃣"]), newText: "foo()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Lib",
          deprecated: false,
          sortText: nil,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(newFilePositions["2️⃣"]), newText: "self")
          )
        ),
      ]
    )

    // Check that we get code completion for `baz` (defined in the new file) in the old file.
    // I.e. check that the existing file's build settings have been updated to include the new file.

    let oldFileCompletions = try await ws.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(oldFileUri), position: oldFilePositions["1️⃣"])
    )
    XCTAssert(oldFileCompletions.items.contains(where: { $0.label == "baz(l: Lib)" }))
  }
}
