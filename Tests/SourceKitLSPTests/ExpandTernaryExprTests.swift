//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
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
@_spi(Testing) import SwiftLanguageService
import SwiftParser
import SwiftSyntax
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

final class ExpandTernaryExprTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String = "Expand ternary expression",
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(input, uri: uri)

    // Determine range
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
      XCTFail("Expected code actions response")
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

  // MARK: - Basic Ternary Expansion Tests

  func testExpandSimpleTernary() async throws {
    try await validateCodeAction(
      input: """
        let x = 1️⃣a ? b : c
        """,
      expectedOutput: """
        let x = if a {
            b
        } else {
            c
        }
        """
    )
  }

  func testExpandTernaryWithComplexCondition() async throws {
    try await validateCodeAction(
      input: """
        let result = 1️⃣(x > 0 && y < 10) ? value1 : value2
        """,
      expectedOutput: """
        let result = if (x > 0 && y < 10) {
            value1
        } else {
            value2
        }
        """
    )
  }

  func testExpandTernaryWithFunctionCalls() async throws {
    try await validateCodeAction(
      input: """
        let x = 1️⃣isValid ? doA() : doB()
        """,
      expectedOutput: """
        let x = if isValid {
            doA()
        } else {
            doB()
        }
        """
    )
  }

  func testExpandTernaryWithStringLiterals() async throws {
    try await validateCodeAction(
      input: """
        let message = 1️⃣flag ? "yes" : "no"
        """,
      expectedOutput: """
        let message = if flag {
            "yes"
        } else {
            "no"
        }
        """
    )
  }

  // MARK: - Return Statement Tests

  func testExpandReturnTernary() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int {
            1️⃣return condition ? a : b
        }
        """,
      expectedOutput: """
        func test() -> Int {
            if condition {
                return a
            } else {
                return b
            }
        }
        """
    )
  }

  func testExpandReturnTernaryWithComplexExpressions() async throws {
    try await validateCodeAction(
      input: """
        func getValue() -> String {
            1️⃣return isEnabled ? enabledValue() : disabledValue()
        }
        """,
      expectedOutput: """
        func getValue() -> String {
            if isEnabled {
                return enabledValue()
            } else {
                return disabledValue()
            }
        }
        """
    )
  }

  // MARK: - Indentation Preservation Tests

  func testExpandTernaryPreservesIndentation() async throws {
    try await validateCodeAction(
      input: """
        func test() {
            if true {
                let x = 1️⃣a ? b : c
            }
        }
        """,
      expectedOutput: """
        func test() {
            if true {
                let x = if a {
                    b
                } else {
                    c
                }
            }
        }
        """
    )
  }

  func testExpandReturnTernaryPreservesIndentation() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int {
            if true {
                1️⃣return condition ? a : b
            }
            return 0
        }
        """,
      expectedOutput: """
        func test() -> Int {
            if true {
                if condition {
                    return a
                } else {
                    return b
                }
            }
            return 0
        }
        """
    )
  }

  // MARK: - Edge Cases

  func testExpandTernaryNotOfferedInsideCodeBlock() async throws {
    // When cursor is inside a code block (not on a ternary), should not offer the action
    try await validateCodeAction(
      input: """
        func test() {
            let x = a ? b : c
            1️⃣print(x)
        }
        """,
      expectedOutput: nil
    )
  }

  func testExpandTernaryWithNilLiteral() async throws {
    try await validateCodeAction(
      input: """
        let x: Int? = 1️⃣hasValue ? value : nil
        """,
      expectedOutput: """
        let x: Int? = if hasValue {
            value
        } else {
            nil
        }
        """
    )
  }

  func testExpandTernaryWithMemberAccess() async throws {
    try await validateCodeAction(
      input: """
        let x = 1️⃣obj.isEnabled ? obj.enabledValue : obj.disabledValue
        """,
      expectedOutput: """
        let x = if obj.isEnabled {
            obj.enabledValue
        } else {
            obj.disabledValue
        }
        """
    )
  }
}
