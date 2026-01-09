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
    expectedOutput: String,
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

    guard let action = codeActions.first(where: { $0.title == title }) else {
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

    var resultingText = cleanInput
    let lineTable = LineTable(cleanInput)

    let sortedEdits = changes.sorted {
      (a: TextEdit, b: TextEdit) -> Bool in
      return a.range.lowerBound > b.range.lowerBound
    }

    for edit in sortedEdits {
      let startIndex = lineTable.stringIndexOf(
        line: edit.range.lowerBound.line,
        utf16Column: edit.range.lowerBound.utf16index
      )
      let endIndex = lineTable.stringIndexOf(
        line: edit.range.upperBound.line,
        utf16Column: edit.range.upperBound.utf16index
      )
      resultingText.replaceSubrange(startIndex..<endIndex, with: edit.newText)
    }

    XCTAssertEqual(resultingText, expectedOutput, file: file, line: line)
  }

  /// Tests if-to-guard conversion eligibility directly without LSP overhead.
  private func assertConvertibleToGuard(
    _ input: String,
    expected: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let sourceFile = Parser.parse(source: input)
    guard let ifExpr = findFirstIfExpr(in: sourceFile) else {
      XCTFail("Could not find if expression in input", file: file, line: line)
      return
    }
    XCTAssertEqual(
      ConvertIfLetToGuard.isConvertibleToGuard(ifExpr),
      expected,
      file: file,
      line: line
    )
  }

  /// Recursively find the first if expression in a syntax tree.
  private func findFirstIfExpr(in node: some SyntaxProtocol) -> IfExprSyntax? {
    if let ifExpr = node.as(IfExprSyntax.self) {
      return ifExpr
    }
    for child in node.children(viewMode: .sourceAccurate) {
      if let found = findFirstIfExpr(in: child) {
        return found
      }
    }
    return nil
  }

  /// Tests guard-to-if conversion eligibility directly without LSP overhead.
  private func assertConvertibleToIfLet(
    _ input: String,
    expected: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let sourceFile = Parser.parse(source: input)
    guard let guardStmt = findFirstGuardStmt(in: sourceFile) else {
      XCTFail("Could not find guard statement in input", file: file, line: line)
      return
    }
    XCTAssertEqual(
      ConvertGuardToIfLet.isConvertibleToIfLet(guardStmt),
      expected,
      file: file,
      line: line
    )
  }

  /// Recursively find the first guard statement in a syntax tree.
  private func findFirstGuardStmt(in node: some SyntaxProtocol) -> GuardStmtSyntax? {
    if let guardStmt = node.as(GuardStmtSyntax.self) {
      return guardStmt
    }
    for child in node.children(viewMode: .sourceAccurate) {
      if let found = findFirstGuardStmt(in: child) {
        return found
      }
    }
    return nil
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
          guard let value = optional  else {
            return nil
          }
          print(value)
          return value
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertGuardToIfLet() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣guard let value = optional else {
            return nil
          }
          print(value)
          return value
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          if let value = optional {
            print(value)
            return value
          }
          return nil
        }
        """,
      title: "Convert to if"
    )
  }

  func testConvertIfLetToGuardNotShownWithoutEarlyExit() throws {
    try assertConvertibleToGuard(
      """
      func test() {
        if let value = optional {
          print(value)
        }
      }
      """,
      expected: false
    )
  }

  func testConvertIfLetToGuardShownWithReturn() throws {
    try assertConvertibleToGuard(
      """
      func test() -> Int? {
        if let value = optional {
          return value
        }
      }
      """,
      expected: true
    )
  }

  func testConvertIfLetToGuardShownWithThrow() throws {
    try assertConvertibleToGuard(
      """
      func test() throws -> Int {
        if let value = optional {
          throw MyError()
        }
      }
      """,
      expected: true
    )
  }

  func testConvertIfLetToGuardShownWithBreak() throws {
    try assertConvertibleToGuard(
      """
      func test() {
        while true {
          if let value = optional {
            break
          }
        }
      }
      """,
      expected: true
    )
  }

  func testConvertIfLetToGuardShownWithContinue() throws {
    try assertConvertibleToGuard(
      """
      func test() {
        while true {
          if let value = optional {
            continue
          }
        }
      }
      """,
      expected: true
    )
  }

  // fatalError requires type information to verify Never return type,
  // so we conservatively treat it as non-exiting (see statementGuaranteesExit docs).
  func testConvertIfLetToGuardNotShownWithFatalError() throws {
    try assertConvertibleToGuard(
      """
      func test() -> Int {
        if let value = optional {
          fatalError("unreachable")
        }
      }
      """,
      expected: false
    )
  }

  func testConvertIfLetToGuardShownWithIfElseBothExiting() throws {
    // Note: Nested if-else as last statement should be detected as exiting
    // when both branches guarantee exit.
    try assertConvertibleToGuard(
      """
      func test() -> Int? {
        if let value = optional {
          if value > 0 {
            return value
          } else {
            return nil
          }
        }
      }
      """,
      expected: true
    )
  }

  func testConvertIfLetToGuardNotShownWithElse() throws {
    try assertConvertibleToGuard(
      """
      func test() {
        if let value = optional {
          print(value)
        } else {
          print("none")
        }
      }
      """,
      expected: false
    )
  }

  func testConvertIfLetToGuardNotShownWithDefer() throws {
    try assertConvertibleToGuard(
      """
      func test() -> Int? {
        if let value = optional {
          defer { cleanup(value) }
          return value
        }
      }
      """,
      expected: false
    )
  }

  func testConvertIfLetToGuardNotShownWithCasePattern() throws {
    try assertConvertibleToGuard(
      """
      func test() -> Int? {
        if case let .some(value) = optional {
          return value
        }
      }
      """,
      expected: false
    )
  }

  func testConvertIfLetToGuardNotShownWithSwitchExit() throws {
    // Switch statements are conservatively treated as not guaranteeing exit
    // even if all cases return, because checking exhaustiveness is complex.
    // TODO: A future implementation could analyze switch exhaustiveness.
    try assertConvertibleToGuard(
      """
      func test() -> Int? {
        if let value = optional {
          switch value {
          case 0: return nil
          default: return value
          }
        }
      }
      """,
      expected: false
    )
  }

  func testConvertGuardToIfNotShownWithCasePattern() throws {
    try assertConvertibleToIfLet(
      """
      func test() {
        guard case let .some(value) = optional else {
          return
        }
        print(value)
      }
      """,
      expected: false
    )
  }

  func testConvertGuardToIfNotShownWithDefer() throws {
    try assertConvertibleToIfLet(
      """
      func test() {
        guard let value = optional else {
          defer { cleanup() }
          return
        }
        print(value)
      }
      """,
      expected: false
    )
  }

  func testConvertGuardToIfNotShownWithoutFollowingCode() async throws {
    // This test must remain an integration test because "no following code"
    // is checked at the codeActions() level, not in isConvertibleToIfLet().
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣guard let value = optional else {
          return
        }
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: Range(positions["1️⃣"]),
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }

    let convertAction = codeActions.first { action in
      action.title == "Convert to if"
    }
    XCTAssertNil(convertAction, "Should NOT offer 'Convert to if' without following code")
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
          guard let value = optional /* unwrap */  else {
            return nil // fallback
          }
          print(value) // Use the value
          return value // return it
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertGuardToIfLetWithComments() async throws {
    // Note: Comments on statements have their leading trivia replaced
    // during the transformation. Inline/trailing comments are preserved.
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          // Ensure we have a value
          1️⃣guard let value = optional /* unwrap */ else {
            return nil // early exit
          }
          print(value) // Process the value
          return value // success
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          // Ensure we have a value
          if let value = optional /* unwrap */ {
            print(value) // Process the value
            return value // success
          }
          return nil // early exit
        }
        """,
      title: "Convert to if"
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
          guard let a = optA, let b = optB, a > 0  else {
            return nil
          }
          return a + b
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertIfLetToGuardPreserves3SpaceIndent() async throws {
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
           guard let value = optional  else {
              return nil
           }
           print(value)
           return value
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertGuardToIfLetPreserves3SpaceIndent() async throws {
    try await validateCodeAction(
      input: """
        func test() -> Int? {
           1️⃣guard let value = optional else {
              return nil
           }
           print(value)
           return value
        }
        """,
      expectedOutput: """
        func test() -> Int? {
           if let value = optional {
              print(value)
              return value
           }
           return nil
        }
        """,
      title: "Convert to if"
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
            guard let inner = optB  else {
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
          guard let outer = optA  else {
            return nil
          }
          print(outer)
          return outer
        }
        """,
      title: "Convert to guard"
    )
  }

  func testConvertGuardToIfLetWithSingleLineBody() async throws {
    // When guard body is on a single line, ensure proper indentation is applied
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          1️⃣guard let value = optional else { return nil }
          print(value)
          return value
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          if let value = optional {
            print(value)
            return value
          }
          return nil
        }
        """,
      title: "Convert to if"
    )
  }

  func testConvertGuardToIfSelectsInnermostCandidate() async throws {
    // When there are multiple guards, cursor position determines which one
    try await validateCodeAction(
      input: """
        func test() -> Int? {
          guard let a = optA else { return nil }
          1️⃣guard let b = optB else { return nil }
          return a + b
        }
        """,
      expectedOutput: """
        func test() -> Int? {
          guard let a = optA else { return nil }
          if let b = optB {
            return a + b
          }
          return nil
        }
        """,
      title: "Convert to if"
    )
  }
}
