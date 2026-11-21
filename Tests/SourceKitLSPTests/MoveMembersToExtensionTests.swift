//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project.
//
// Copyright 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception.
//
// See https://swift.org/LICENSE.txt for license information.
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors.
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import XCTest

private typealias CodeActionCapabilities = TextDocumentClientCapabilities.CodeAction
private typealias CodeActionLiteralSupport = CodeActionCapabilities.CodeActionLiteralSupport
private typealias CodeActionKindCapabilities = CodeActionLiteralSupport.CodeActionKindValueSet

private let clientCapabilitiesWithCodeActionSupport: ClientCapabilities = {
  var documentCapabilities = TextDocumentClientCapabilities()
  var codeActionCapabilities = CodeActionCapabilities()
  codeActionCapabilities.codeActionLiteralSupport = .init(
    codeActionKind: .init(valueSet: [.refactorInline])
  )
  documentCapabilities.codeAction = codeActionCapabilities
  return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
}()

final class MoveMembersToExtensionTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String = "Move to extension",
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let testClient = try await TestSourceKitLSPClient(
      capabilities: clientCapabilitiesWithCodeActionSupport
    )
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(input, uri: uri)

    let pos = try XCTUnwrap(positions["1️⃣"], file: file, line: line)
    let request = CodeActionRequest(
      range: pos..<pos,
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)

    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response", file: file, line: line)
      return
    }

    let action = codeActions.first(where: { $0.title == title })
    if let expectedOutput {
      guard let action else {
        let available = codeActions.map(\.title)
        XCTFail(
          "Action '\(title)' not found. Available: \(available)",
          file: file, line: line
        )
        return
      }
      guard let edit = action.edit else {
        XCTFail("Action '\(title)' has no edit", file: file, line: line)
        return
      }
      let changes = edit.changes?[uri] ?? []
      let cleanInput = extractMarkers(input).textWithoutMarkers
      let resultingText = apply(edits: changes, to: cleanInput)
      XCTAssertEqual(resultingText, expectedOutput, file: file, line: line)
    } else {
      XCTAssertNil(
        action,
        "Expected action '\(title)' to not be offered",
        file: file, line: line
      )
    }
  }

  func testMoveFunction() async throws {
    try await validateCodeAction(
      input: """
      struct Counter {
        var total = 0
        func 1️⃣increment() {}
      }
      """,
      expectedOutput: """
      struct Counter {
        var total = 0

      }

      extension Counter {
        func increment() {}
      }
      """
    )
  }

  func testMoveComputedProperty() async throws {
    try await validateCodeAction(
      input: """
      struct Counter {
        var 1️⃣doubled: Int {
          total * 2
        }
      }
      """,
      expectedOutput: """
      struct Counter {

      }

      extension Counter {
        var doubled: Int {
          total * 2
        }
      }
      """
    )
  }

  func testMoveInitializer() async throws {
    try await validateCodeAction(
      input: """
      struct Counter {
        1️⃣init(value: Int) {}
      }
      """,
      expectedOutput: """
      struct Counter {

      }

      extension Counter {
        init(value: Int) {}
      }
      """
    )
  }

  func testStoredPropertyNotOffered() async throws {
    try await validateCodeAction(
      input: """
      struct Counter {
        var 1️⃣total = 0
      }
      """,
      expectedOutput: nil
    )
  }

  func testDeinitNotOffered() async throws {
    try await validateCodeAction(
      input: """
      class Resource {
        1️⃣deinit {}
      }
      """,
      expectedOutput: nil
    )
  }

  func testNestedTypeNotOffered() async throws {
    try await validateCodeAction(
      input: """
      struct Outer {
        struct Inner {
          func 1️⃣work() {}
        }
      }
      """,
      expectedOutput: nil
    )
  }
}
