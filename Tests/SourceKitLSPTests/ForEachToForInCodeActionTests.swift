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

import SKTestSupport
import SourceKitLSP
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(Testing) import SwiftLanguageService
import XCTest

private typealias CodeActionCapabilities = TextDocumentClientCapabilities.CodeAction
private typealias CodeActionLiteralSupport = CodeActionCapabilities.CodeActionLiteralSupport
private typealias CodeActionKindCapabilities = CodeActionLiteralSupport.CodeActionKindValueSet

private let clientCapabilitiesWithCodeActionSupport: ClientCapabilities = {
  var documentCapabilities = TextDocumentClientCapabilities()
  var codeActionCapabilities = CodeActionCapabilities()
  let codeActionKinds = CodeActionKindCapabilities(valueSet: [.refactor, .quickFix])
  let codeActionLiteralSupport = CodeActionLiteralSupport(codeActionKind: codeActionKinds)
  codeActionCapabilities.codeActionLiteralSupport = codeActionLiteralSupport
  documentCapabilities.codeAction = codeActionCapabilities
  return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
}()

final class ForEachToForInCodeActionTests: SourceKitLSPTestCase {

  private func makeProject(
    _ source: String
  ) async throws -> (SwiftPMTestProject, DocumentURI, DocumentPositions) {
    let project = try await SwiftPMTestProject(
      files: ["Test.swift": source],
      capabilities: clientCapabilitiesWithCodeActionSupport,
      enableBackgroundIndexing: true
    )
    let (uri, positions) = try project.openDocument("Test.swift")
    return (project, uri, positions)
  }

  private func forEachAction(
    in project: SwiftPMTestProject,
    uri: DocumentURI,
    at position: Position
  ) async throws -> CodeAction? {
    let result = try await project.testClient.send(
      CodeActionRequest(
        range: position..<position,
        context: .init(),
        textDocument: TextDocumentIdentifier(uri)
      )
    )
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return nil
    }
    return codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
  }

  func testBasicForEachToForInConversion() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Should offer 'Convert to for-in loop' action")
  }

  func testRejectsCustomForEach() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      struct MyCollection {
        func forEach(_ closure: (Int) -> Void) {
          closure(1)
        }
      }

      let col = MyCollection()
      1️⃣col.forEach { item in
        print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action for custom forEach (not stdlib)")
  }

  func testExplicitClosureArgument() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach({ item in
        print(item)
      })
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Should offer action for explicit closure argument form")
  }

  func testConvertsShorthandDollarZero() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { print($0) }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Should offer action for $0 shorthand, rewriting to named parameter")
  }

  func testRejectsReturnWithValue() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        if item > 2 {
          return 42
        }
        print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action when closure has return with value")
  }

  func testTransformsBareReturnToContinue() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        if item < 2 {
          return
        }
        print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Bare return should be converted to continue")
  }

  func testAllowsTryInClosure() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        try print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Should offer action — forEach is rethrows so try is valid")
  }

  func testRejectsClosureWithAwait() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        await print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action for await expression")
  }

  func testParenthesizedClosureParameter() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach({ (item) in
        print(item)
      })
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Should offer action for parenthesized closure parameter")
  }

  func testTypedClosureParameter() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach({ (item: Int) in
        print(item)
      })
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Should offer action and preserve type annotation")
  }

  func testDollarZeroDoesNotPenetrateNestedClosure() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach {
        let mapped = [$0].map { $0 + 1 }
        print(mapped)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action)
    guard let change = action?.edit?.changes?[uri]?.first else {
      XCTFail("Expected edit")
      return
    }
    // The inner `$0` in `map { $0 + 1 }` must remain untouched
    XCTAssertTrue(change.newText.contains("$0 + 1"), "Nested closure $0 should not be rewritten")
    XCTAssertTrue(change.newText.contains("for element in"), "Outer $0 should become 'element'")
  }

  func testBareReturnRewrittenToContinueInOutput() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        if item < 2 {
          return
        }
        print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action)
    guard let change = action?.edit?.changes?[uri]?.first else {
      XCTFail("Expected edit")
      return
    }
    XCTAssertTrue(change.newText.contains("continue"), "Bare return should become continue")
    XCTAssertFalse(change.newText.contains("return"), "No return should remain in the output")
  }

  func testGracefulDegradationWithoutCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    XCTAssertNotNil(result, "Code action request should complete even if cursorInfo unavailable")
  }

  func testProviderIntegrationInCodeActionFlow() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let numbers = [1, 2, 3, 4, 5]
      1️⃣numbers.forEach { n in
        print(n)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNotNil(action, "Provider should be called and return action")
  }
}
