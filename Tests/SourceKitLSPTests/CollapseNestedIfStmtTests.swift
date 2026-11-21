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

final class CollapseNestedIfStmtTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String = "Collapse nested if statements",
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

  func testSimpleCollapse() async throws {
    try await validateCodeAction(
      input: """
      func f() {
        1️⃣if a {
          if b {
            doWork()
          }
        }
      }
      """,
      expectedOutput: """
      func f() {
        if a, b {
          doWork()
        }
      }
      """
    )
  }

  func testCursorOnInnerIf() async throws {
    try await validateCodeAction(
      input: """
      func f() {
        if a {
          1️⃣if b {
            doWork()
          }
        }
      }
      """,
      expectedOutput: """
      func f() {
        if a, b {
          doWork()
        }
      }
      """
    )
  }

  func testOuterWithElseNotOffered() async throws {
    try await validateCodeAction(
      input: """
      func f() {
        1️⃣if a {
          if b {
            doWork()
          }
        } else {
          other()
        }
      }
      """,
      expectedOutput: nil
    )
  }

  func testInnerWithElseNotOffered() async throws {
    try await validateCodeAction(
      input: """
      func f() {
        1️⃣if a {
          if b {
            doWork()
          } else {
            other()
          }
        }
      }
      """,
      expectedOutput: nil
    )
  }

  func testOuterBodyWithMultipleStatementsNotOffered() async throws {
    try await validateCodeAction(
      input: """
      func f() {
        1️⃣if a {
          setup()
          if b {
            doWork()
          }
        }
      }
      """,
      expectedOutput: nil
    )
  }

  func testTripleNestingCollapsesTwoLevels() async throws {
    try await validateCodeAction(
      input: """
      func f() {
        1️⃣if a {
          if b {
            if c {
              doWork()
            }
          }
        }
      }
      """,
      expectedOutput: """
      func f() {
        if a, b {
          if c {
            doWork()
          }
        }
      }
      """
    )
  }
}
