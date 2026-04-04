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
    try await forEachAction(in: project, uri: uri, range: position..<position, context: .init())
  }

  private func forEachAction(
    in project: SwiftPMTestProject,
    uri: DocumentURI,
    range: Range<Position>,
    context: CodeActionContext
  ) async throws -> CodeAction? {
    let result = try await project.testClient.send(
      CodeActionRequest(
        range: range,
        context: context,
        textDocument: TextDocumentIdentifier(uri)
      )
    )
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return nil
    }
    return codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
  }

  private func forEachReplacementText(
    in project: SwiftPMTestProject,
    uri: DocumentURI,
    at position: Position
  ) async throws -> String? {
    let action = try await forEachAction(in: project, uri: uri, at: position)
    return action?.edit?.changes?[uri]?.first?.newText
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
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for item in array {
        print(item)
      }
      """
    )
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
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for item in array {
        print(item)
      }
      """
    )
  }

  func testConvertsShorthandDollarZero() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { print($0) }
      """
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for element in array {\n  print(element)\n}")
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
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for item in array {
        print(item)
      }
      """
    )
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
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for item: Int in array {
        print(item)
      }
      """
    )
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

  func testSelectionRangeBoundaries() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      1️⃣func test() {
        let array = [1, 2, 3]
        2️⃣array.reversed().3️⃣forEach4️⃣ { item in
          print(item)
        }5️⃣
      }6️⃣
      """
    )

    let action24 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["2️⃣"]..<positions["4️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action24)

    let action25 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["2️⃣"]..<positions["5️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action25)

    let action33 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["3️⃣"]..<positions["3️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action33)

    let action34 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["3️⃣"]..<positions["4️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action34)

    let action35 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["3️⃣"]..<positions["5️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action35)

    let action16 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["1️⃣"]..<positions["6️⃣"],
      context: .init()
    )
    XCTAssertNil(action16, "Should not offer the action when the selection only broadly contains the forEach call")
  }

  func testDoesNotOfferActionInsideClosureBody() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.forEach { item in
        1️⃣print(item)
      }
      """
    )

    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "The action should only be offered on the forEach call/selection, not inside the closure body")
  }

}
