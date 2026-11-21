//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import XCTest

private let clientCapabilitiesWithCodeActionSupport: ClientCapabilities = {
  var documentCapabilities = TextDocumentClientCapabilities()
  var codeActionCapabilities = TextDocumentClientCapabilities.CodeAction()
  codeActionCapabilities.codeActionLiteralSupport = .init(
    codeActionKind: .init(valueSet: [.refactorInline])
  )
  documentCapabilities.codeAction = codeActionCapabilities
  return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
}()

final class ExpandTernaryExprTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String = "Expand ternary expression",
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

  func testAssignmentForm() async throws {
    try await validateCodeAction(
      input: """
      result = cond1️⃣ ? a() : b()
      """,
      expectedOutput: """
      if cond {
          result = a()
      } else {
          result = b()
      }
      """
    )
  }

  func testBindingFormWithExplicitType() async throws {
    try await validateCodeAction(
      input: """
      let result: Int = cond ? 1️⃣a() : b()
      """,
      expectedOutput: """
      let result: Int
      if cond {
          result = a()
      } else {
          result = b()
      }
      """
    )
  }

  func testBindingWithoutWrittenTypeNotOffered() async throws {
    try await validateCodeAction(
      input: """
      let result = cond 1️⃣? a() : b()
      """,
      expectedOutput: nil
    )
  }

  func testNonTernaryAssignmentNotOffered() async throws {
    try await validateCodeAction(
      input: """
      result = cond && other1️⃣
      """,
      expectedOutput: nil
    )
  }

  func testComplexOperands() async throws {
    try await validateCodeAction(
      input: """
      if true1️⃣ {} 
      other.value = (x + y) ? f(a, b) : g(c)
      """,
      expectedOutput: nil
    )
  }
}
