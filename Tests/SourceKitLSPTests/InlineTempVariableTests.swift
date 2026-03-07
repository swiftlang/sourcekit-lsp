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
import SKUtilities
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
  documentCapabilities.completion = .init(completionItem: .init(snippetSupport: true))
  return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
}()

final class InlineTempVariableTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String = "Inline variable",
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(input, uri: uri)

    let range: Range<Position>
    if input.contains("1️⃣") && input.contains("2️⃣") {
      range = positions["1️⃣"]..<positions["2️⃣"]
    } else if input.contains("1️⃣") {
      let pos = positions["1️⃣"]
      range = pos..<pos
    } else {
      XCTFail("Missing marker 1️⃣ in input", file: file, line: line)
      return
    }

    let request = CodeActionRequest(
      range: range,
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
        XCTFail("Action '\(title)' not found. Available: \(available)", file: file, line: line)
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
      XCTAssertNil(action, "Expected action '\(title)' to be not offered", file: file, line: line)
    }
  }

  func testInlineTempVariableSimple() async throws {
    try await validateCodeAction(
      input: """
        func example() {
            let 1️⃣basePrice = item.price
            let total = basePrice * quantity
        }
        """,
      expectedOutput: """
        func example() {
            let total = item.price * quantity
        }
        """
    )
  }

  func testInlineTempVariableWithParenthesesForPrecedence() async throws {
    try await validateCodeAction(
      input: """
        func example() {
            let 1️⃣basePrice = 1 + 2
            let total = basePrice * 3
        }
        """,
      expectedOutput: """
        func example() {
            let total = (1 + 2) * 3
        }
        """
    )
  }

  func testInlineTempVariableMultipleUsages() async throws {
    try await validateCodeAction(
      input: """
        func example() {
            let 1️⃣x = foo()
            let a = x + 1
            let b = x * 2
        }
        """,
      expectedOutput: """
        func example() {
            let a = foo() + 1
            let b = foo() * 2
        }
        """
    )
  }

  func testInlineTempVariableNotShownWhenNoUsages() async throws {
    try await validateCodeAction(
      input: """
        func example() {
            let 1️⃣basePrice = item.price
        }
        """,
      expectedOutput: nil
    )
  }
}
