//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project.
//
// Copyright 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception.
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
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

final class ExtractExprTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String = "Extract expression",
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

  func testExtractBinaryExpression() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          let a = 1
          print(a + (1️⃣2 * 3))
        }
        """,
      expectedOutput: """
        func demo() {
          let a = 1
          let result = 2 * 3
          print(a + (result))
        }
        """
    )
  }

  func testExtractDoesNotOfferOnOperator() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          let a = 1
          print(a + 2 1️⃣* 3)
        }
        """,
      expectedOutput: nil
    )
  }

  func testExtractFunctionCallArgumentExpression() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          let names = ["bob", "carl"]
          process(names.joi1️⃣ned())
        }
        """,
      expectedOutput: """
        func demo() {
          let names = ["bob", "carl"]
          let result = names.joined()
          process(result)
        }
        """
    )
  }

  func testExtractAvoidsNameCollision() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          let result = 1
          print(2 + 1️⃣3)
        }
        """,
      expectedOutput: nil
    )
  }

  func testExtractDoesNotOfferOnBareIdentifier() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          let a = 1
          print(a1️⃣)
        }
        """,
      expectedOutput: nil
    )
  }

  func testExtractDoesNotOfferOnLiteral() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          print(1 + 1️⃣2)
        }
        """,
      expectedOutput: nil
    )
  }

  func testExtractDoesNotOfferOnClosure() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          doWork { _ in 1️⃣ }
        }
        """,
      expectedOutput: nil
    )
  }

  func testExtractDoesNotOfferInTypeScope() async throws {
    try await validateCodeAction(
      input: """
        struct Counter {
          var total: Int = 1 + 1️⃣2
        }
        """,
      expectedOutput: nil
    )
  }

  func testExtractSubscriptCallExpression() async throws {
    try await validateCodeAction(
      input: """
        func demo() {
          let matrix = [[1, 2], [3, 4]]
          save(matrix[1️⃣0])
        }
        """,
      expectedOutput: """
        func demo() {
          let matrix = [[1, 2], [3, 4]]
          let result = matrix[0]
          save(result)
        }
        """
    )
  }
}
