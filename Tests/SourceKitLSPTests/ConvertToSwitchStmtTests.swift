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

final class ConvertToSwitchStmtTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String = "Convert to switch statement",
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

  func testEqualityChain() async throws {
    try await validateCodeAction(
      input: """
      1️⃣if status == .loading {
        showSpinner()
      } else if status == .done {
        showContent()
      } else {
        showError()
      }
      """,
      expectedOutput: """
      switch status {
        case .loading:
          showSpinner()
        case .done:
          showContent()
        default:
          showError()
      }
      """
    )
  }

  func testNumericLiterals() async throws {
    try await validateCodeAction(
      input: """
      1️⃣if value == 1 {
        a()
      } else if value == 2 {
        b()
      } else {
        c()
      }
      """,
      expectedOutput: """
      switch value {
        case 1:
          a()
        case 2:
          b()
        default:
          c()
      }
      """
    )
  }

  func testCursorOnElseIf() async throws {
    try await validateCodeAction(
      input: """
      if value == 1 {
        a()
      } else 1️⃣if value == 2 {
        b()
      } else {
        c()
      }
      """,
      expectedOutput: """
      switch value {
        case 1:
          a()
        case 2:
          b()
        default:
          c()
      }
      """
    )
  }

  func testCasePatternConditions() async throws {
    try await validateCodeAction(
      input: """
      1️⃣if case .some = result {
        present()
      } else if case .failure = result {
        report()
      } else {
        break
      }
      """,
      expectedOutput: """
      switch result {
        case .some:
          present()
        case .failure:
          report()
        default:
          break
      }
      """
    )
  }

  func testNoElseProducesDefaultBreak() async throws {
    try await validateCodeAction(
      input: """
      1️⃣if value == 1 {
        a()
      } else if value == 2 {
        b()
      }
      """,
      expectedOutput: """
      switch value {
        case 1:
          a()
        case 2:
          b()
        default:
          break
      }
      """
    )
  }

  func testExtraConditionNotOffered() async throws {
    try await validateCodeAction(
      input: """
      1️⃣if value == 1, flag {
        a()
      } else if value == 2 {
        b()
      } else {
        c()
      }
      """,
      expectedOutput: nil
    )
  }

  func testDifferentVariablesNotOffered() async throws {
    try await validateCodeAction(
      input: """
      1️⃣if value == 1 {
        a()
      } else if other == 2 {
        b()
      } else {
        c()
      }
      """,
      expectedOutput: nil
    )
  }

  func testSingleIfWithoutElseNotOffered() async throws {
    try await validateCodeAction(
      input: """
      1️⃣if value == 1 {
        a()
      }
      """,
      expectedOutput: nil
    )
  }
}
