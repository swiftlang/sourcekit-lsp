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
@_spi(Testing) import SwiftLanguageService
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

final class ForEachToForInTests: SourceKitLSPTestCase {
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

    let matchingActions = codeActions.filter { $0.title == title }
    XCTAssertLessThanOrEqual(
      matchingActions.count,
      1,
      "Expected at most one action named '\(title)', found \(matchingActions.count)",
      file: file,
      line: line
    )

    let action = matchingActions.first
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

  func testConvertForEachToForIn() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [String]) {
          1️⃣array.forEach { item in
            print(item)
          }
        }
        """,
      expectedOutput: """
        func test(array: [String]) {
          for item in array {
            print(item)
          }
        }
        """,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInInsideClosureBody() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [String]) {
          array.forEach { item in
            1️⃣print(item)
          }
        }
        """,
      expectedOutput: """
        func test(array: [String]) {
          for item in array {
            print(item)
          }
        }
        """,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInReturnToContinue() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [String]) {
          1️⃣array.forEach { item in
            if item.isEmpty { return }
            print(item)
          }
        }
        """,
      expectedOutput: """
        func test(array: [String]) {
          for item in array {
            if item.isEmpty { continue }
            print(item)
          }
        }
        """,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInNestedClosureReturnNotConverted() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [[Int]]) {
          1️⃣array.forEach { item in
            let mapped = item.map { return $0 + 1 }
            print(mapped)
          }
        }
        """,
      expectedOutput: """
        func test(array: [[Int]]) {
          for item in array {
            let mapped = item.map { return $0 + 1 }
            print(mapped)
          }
        }
        """,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInLocalTypeReturnsNotConverted() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [Int]) {
          1️⃣array.forEach { item in
            struct Local {
              var value: Int {
                return 1
              }

              init() {
                return
              }
            }

            if item == 0 { return }
            _ = Local().value
          }
        }
        """,
      expectedOutput: """
        func test(array: [Int]) {
          for item in array {
            struct Local {
              var value: Int {
                return 1
              }

              init() {
                return
              }
            }

            if item == 0 { continue }
            _ = Local().value
          }
        }
        """,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInChainedCall() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [Int]) {
          1️⃣array.filter { value in value > 0 }.forEach { item in
            print(item)
          }
        }
        """,
      expectedOutput: """
        func test(array: [Int]) {
          for item in array.filter { value in value > 0 } {
            print(item)
          }
        }
        """,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachParenthesizedClosure() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [String]) {
          1️⃣array.forEach({ item in
            print(item)
          })
        }
        """,
      expectedOutput: """
        func test(array: [String]) {
          for item in array {
            print(item)
          }
        }
        """,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInNotShownForAdditionalTrailingClosures() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [String]) {
          1️⃣array.forEach { item in
            print(item)
          } extra: {
            print("extra")
          }
        }
        """,
      expectedOutput: nil,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInNotShownForShorthandParameter() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [String]) {
          1️⃣array.forEach {
            print($0)
          }
        }
        """,
      expectedOutput: nil,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInNotShownForNestedClosureCursor() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [[Int]]) {
          array.forEach { item in
            let mapped = item.map { value in
              1️⃣print(value)
            }
            print(mapped)
          }
        }
        """,
      expectedOutput: nil,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInNotShownForNonStatementPosition() async throws {
    try await validateCodeAction(
      input: """
        func test(array: [String]) {
          let _ = 1️⃣array.forEach { item in
            print(item)
          }
        }
        """,
      expectedOutput: nil,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInNotShownWithoutBase() async throws {
    try await validateCodeAction(
      input: """
        func forEach(_ body: (Int) -> Void) {}

        func test() {
          1️⃣forEach { value in
            print(value)
          }
        }
        """,
      expectedOutput: nil,
      title: "Convert to 'for-in' loop"
    )
  }

  func testConvertForEachToForInNotShownForCustomForEach() async throws {
    try await validateCodeAction(
      input: """
        struct Numbers {
          func forEach(_ body: (Int) -> Void) {
            body(1)
          }
        }

        func test(numbers: Numbers) {
          1️⃣numbers.forEach { value in
            print(value)
          }
        }
        """,
      expectedOutput: nil,
      title: "Convert to 'for-in' loop"
    )
  }
}
