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

final class IfGuardConversionTests: SourceKitLSPTestCase {
  private func validateCodeAction(
    input: String,
    expectedOutput: String?,
    title: String,
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
        let available = codeActions.map { $0.title }
        XCTFail("Action '\(title)' not found. Available: \(available)", file: file, line: line)
        return
      }

      guard let edit = action.edit else {
        XCTFail("Action '\(title)' has no edit", file: file, line: line)
        return
      }

      let changes = edit.changes?[uri] ?? []

      let cleanInput =
        input
        .replacingOccurrences(of: "1️⃣", with: "")
        .replacingOccurrences(of: "2️⃣", with: "")

      let resultingText = apply(edits: changes, to: cleanInput)

      XCTAssertEqual(resultingText, expectedOutput, file: file, line: line)
    } else {
      XCTAssertNil(action, "Expected action '\(title)' to be not offered", file: file, line: line)
    }
  }

  func testConvertIfLetToGuard() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if let value = optional {
            print(value)
            return value
          }
          return nil
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          guard let value = optional else {
            return nil
          }
          print(value)
          return value
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardNotShownWithoutEarlyExit() async throws {
    try await validateCodeAction(
      input: """
        func test() {
          1️⃣if let value = optional {
            print(value)
          }
          return
        }
        """,
      expectedOutput: nil,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardNotShownWhenPartOfExpression() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          if let a = optional {
            let x = 1️⃣if let b = optional { b } else { nil }
            return a
          }
          return nil
        }
        """,
      expectedOutput: nil,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardShownWithReturn() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if let value = optional {
            return value
          }
          return nil
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          guard let value = optional else {
            return nil
          }
          return value
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardShownWithThrow() async throws {
    try await validateCodeAction(
      input: """
        func test() throws -> Int {
          1️⃣if let value = optional {
            throw MyError()
          }
          return 0
        }
        """,
      expectedOutput: """
        func test() throws -> Int {
          guard let value = optional else {
            return 0
          }
          throw MyError()
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardShownWithBreak() async throws {
    try await validateCodeAction(
      input: """
        func test() {
          while true {
            1️⃣if let value = optional {
              break
            }
            print("loop")
          }
        }
        """,
      expectedOutput: """
        func test() {
          while true {
            guard let value = optional else {
              print("loop")
            }
            break
          }
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardShownWithContinue() async throws {
    try await validateCodeAction(
      input: """
        func test() {
          while true {
            1️⃣if let value = optional {
              continue
            }
            print("loop")
          }
        }
        """,
      expectedOutput: """
        func test() {
          while true {
            guard let value = optional else {
              print("loop")
            }
            continue
          }
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardNotShownWithFatalError() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int {
          1️⃣if let value = optional {
            fatalError("unreachable")
          }
          return 0
        }
        """,
      expectedOutput: nil,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardShownWithIfElseBothExiting() async throws {
    // Note: Nested if-else as last statement should be detected as exiting
    // when both branches guarantee exit.
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if let value = optional {
            if value > 0 {
              return value
            } else {
              return nil
            }
          }
          return nil
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          guard let value = optional else {
            return nil
          }
          if value > 0 {
            return value
          } else {
            return nil
          }
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardNotShownWithElse() async throws {
    try await validateCodeAction(
      input: """
        func test() {
          1️⃣if let value = optional {
            print(value)
          } else {
            print("none")
          }
          return
        }
        """,
      expectedOutput: nil,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardNotShownWithDefer() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if let value = optional {
            defer { cleanup(value) }
            return value
          }
          return nil
        }
        """,
      expectedOutput: nil,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardNotShownWithCasePattern() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if case let .some(value) = optional {
            return value
          }
          return nil
        }
        """,
      expectedOutput: nil,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardNotShownWithSwitchExit() async throws {
    // Switch statements are conservatively treated as not guaranteeing exit
    // even if all cases return, because checking exhaustiveness is complex.
    // TODO: A future implementation could analyze switch exhaustiveness.
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if let value = optional {
            switch value {
            case 0: return nil
            default: return value
            }
          }
          return nil
        }
        """,
      expectedOutput: nil,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardWithComments() async throws {
    // Note: Comments inside the if body have their leading trivia replaced
    // during the transformation, so inline comments are preserved but
    // leading comments on the first statement may be adjusted.
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          // Check if we have a value
          1️⃣if let value = optional /* unwrap */ {
            print(value) // Use the value
            return value // return it
          }
          return nil // fallback
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          // Check if we have a value
          guard let value = optional /* unwrap */ else {
            return nil // fallback
          }
          print(value) // Use the value
          return value // return it
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardMultipleConditions() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if let a = optA, let b = optB, a > 0 {
            return a + b
          }
          return nil
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          guard let a = optA, let b = optB, a > 0 else {
            return nil
          }
          return a + b
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardPreserves4SpaceIndent() async throws {
    // BasicFormat.inferIndentation requires at least 3 lines of code to infer indentation.
    try await validateCodeAction(
      input: """
        func test() -> Int? {
            1️⃣if let value = optional {
                print(value)
                print(value)
                print(value)
                return value
            }
            return nil
        }
        """,
      expectedOutput: """
        func test() -> Int? {
            guard let value = optional else {
                return nil
            }
            print(value)
            print(value)
            print(value)
            return value
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardSelectsInnermostCandidate() async throws {
    // When cursor is on inner if-let, only the inner one should be converted
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          if let outer = optA {
            1️⃣if let inner = optB {
              return inner
            }
            return outer
          }
          return nil
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          if let outer = optA {
            guard let inner = optB else {
              return outer
            }
            return inner
          }
          return nil
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardSelectsOuterWhenCursorOnOuter() async throws {
    // When cursor is on outer if-let, only the outer one should be converted
    // (inner doesn't qualify because it doesn't guarantee exit from outer scope)
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣if let outer = optA {
            print(outer)
            return outer
          }
          return nil
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          guard let outer = optA else {
            return nil
          }
          print(outer)
          return outer
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardWithCRLF() async throws {
    // Test that CRLF line endings in input are handled correctly.
    // Note: Swift parser normalizes CRLF to LF internally, but the original document
    // lines not affected by the replacement keep their CRLF endings. The generated
    // guard body uses LF for its internal newlines.
    try await validateCodeAction(
      input:
        "func test() -> Int? {\r\n  1️⃣if let value = optional {\r\n    print(value)\r\n    return value\r\n  }\r\n  return nil\r\n}",
      expectedOutput:
        "func test() -> Int? {\r\n  guard let value = optional else {\n    return nil\n  }\n  print(value)\n  return value\r\n}",
      title: "Convert to guard"
    )
  }

}
