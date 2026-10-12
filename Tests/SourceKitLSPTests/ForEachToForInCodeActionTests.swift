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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import SourceKitD
import SourceKitLSP
@_spi(Testing) import SwiftLanguageService
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
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
  codeActionCapabilities.resolveSupport = .init(properties: ["edit"])
  documentCapabilities.codeAction = codeActionCapabilities
  return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
}()

final class ForEachToForInCodeActionTests: SourceKitLSPTestCase {

  private func makeProject(
    _ source: String,
    supportsResolve: Bool = true
  ) async throws -> (SwiftPMTestProject, DocumentURI, DocumentPositions) {
    var capabilities = clientCapabilitiesWithCodeActionSupport
    if !supportsResolve {
      capabilities.textDocument?.codeAction?.resolveSupport = nil
    }
    let project = try await SwiftPMTestProject(
      files: ["Test.swift": source],
      capabilities: capabilities,
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
    let action = try unwrap(await forEachAction(in: project, uri: uri, at: position))
    let resolved = try await project.testClient.send(CodeActionResolveRequest(codeAction: action))
    return resolved.edit?.changes?[uri]?.first?.newText
  }

  func testBasicForEachToForInConversion() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
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

  func testRejectsCustomForEachOnResolve() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      struct MyCollection {
        func forEach(_ closure: (Int) -> Void) {
          closure(1)
        }
      }

      let col = MyCollection()
      col.1️⃣forEach { item in
        print(item)
      }
      """
    )
    let action = try unwrap(await forEachAction(in: project, uri: uri, at: positions["1️⃣"]))
    XCTAssertNil(action.edit)
    XCTAssertNotNil(action.data)
    await assertThrowsError(try await project.testClient.send(CodeActionResolveRequest(codeAction: action))) { error in
      assertContains(
        (error as? ResponseError)?.message ?? "",
        "Only the Swift standard library's forEach can be converted"
      )
    }
  }

  func testExplicitClosureArgument() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach({ item in
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
      array.1️⃣forEach { print($0) }
      """
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for element in array {\n  print(element)\n}")
  }

  func testRejectsReturnWithValue() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
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
      array.1️⃣forEach { item in
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

  func testTransformsNestedLoopBareReturnToLabeledContinue() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [[1, 2], [3, 4]]
      array.1️⃣forEach { item in
        for value in item {
          if value < 2 {
            return
          }
        }
        print(item)
      }
      """
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      forEachLoop: for item in array {
        for value in item {
          if value < 2 {
            continue forEachLoop
          }
        }
        print(item)
      }
      """
    )
  }

  func testAllowsTryInClosure() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func check(_ value: Int) throws {}
      func run() throws {
        let array = [1, 2, 3]
        2️⃣try array.1️⃣forEach { item in
          try check(item)
        }
      }
      """
    )
    let action = try unwrap(await forEachAction(in: project, uri: uri, at: positions["1️⃣"]))
    let resolved = try await project.testClient.send(CodeActionResolveRequest(codeAction: action))
    let edit = try unwrap(resolved.edit?.changes?[uri]?.first)
    XCTAssertEqual(edit.range.lowerBound, positions["2️⃣"], "The edit must also remove the original try")
    XCTAssertEqual(edit.newText, "for item in try array {\n    try check(item)\n  }")
  }

  func testMovesOuterTryToThrowingSequence() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func makeArray() throws -> [Int] { [1, 2, 3] }
      func run() throws {
        2️⃣try makeArray().1️⃣forEach { print($0) }
      }
      """
    )
    let action = try unwrap(await forEachAction(in: project, uri: uri, at: positions["1️⃣"]))
    let resolved = try await project.testClient.send(CodeActionResolveRequest(codeAction: action))
    let edit = try unwrap(resolved.edit?.changes?[uri]?.first)
    XCTAssertEqual(edit.range.lowerBound, positions["2️⃣"], "The edit must also remove the original try")
    XCTAssertEqual(edit.newText, "for element in try makeArray() {\n    print(element)\n  }")
  }

  func testRejectsTryOptionalAndForcedCalls() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func check(_ value: Int) throws {}
      func run() {
        let array = [1, 2, 3]
        try? array.1️⃣forEach { try check($0) }
        try! array.2️⃣forEach { try check($0) }
      }
      """
    )
    for marker in ["1️⃣", "2️⃣"] {
      let action = try await forEachAction(in: project, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should not offer an action for \(marker) because the outer try changes error handling")
    }
  }

  func testRejectsCallsUsedAsExpressions() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func consume(_ value: Void) {}
      func run() {
        let array = [1, 2, 3]
        let result: Void = array.1️⃣forEach { print($0) }
        consume(array.2️⃣forEach { print($0) })
        consume(result)
      }
      """
    )
    for marker in ["1️⃣", "2️⃣"] {
      let action = try await forEachAction(in: project, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should only offer an action for a standalone forEach statement")
    }
  }

  func testRejectsImplicitReturnValueContexts() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func run() -> Any { [1].1️⃣forEach { print($0) } }
      let callback: () -> Any = { [1].2️⃣forEach { print($0) } }
      var value: Any { [1].3️⃣forEach { print($0) } }
      """
    )
    for marker in ["1️⃣", "2️⃣", "3️⃣"] {
      let action = try await forEachAction(in: project, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should not convert a forEach call used as an implicit return value")
    }
  }

  func testAllowsSoleExpressionInVoidContexts() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func runVoid() { [1].1️⃣forEach { print($0) } }
      let voidCallback = { () -> Void in [1].2️⃣forEach { print($0) } }
      """
    )
    for marker in ["1️⃣", "2️⃣"] {
      let replacement = try unwrap(await forEachReplacementText(in: project, uri: uri, at: positions[marker]))
      XCTAssertTrue(replacement.contains("for element in [1]"))
      XCTAssertTrue(replacement.contains("print(element)"))
    }
  }

  func testIfAndSwitchExpressionBranchesVersusStatements() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func expressions(_ flag: Bool, _ number: Int) {
        let first: Any = if flag {
          [1].1️⃣forEach { print($0) }
        } else {
          ()
        }
        let second: Any = switch number {
        case 0:
          [1].2️⃣forEach { print($0) }
        default:
          ()
        }
        print(first, second)
      }
      func statements(_ flag: Bool, _ number: Int) {
        if flag {
          [1].3️⃣forEach { print($0) }
        }
        switch number {
        case 0:
          [1].4️⃣forEach { print($0) }
        default:
          break
        }
      }
      """
    )
    for marker in ["1️⃣", "2️⃣"] {
      let action = try await forEachAction(in: project, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should not convert a branch used as an expression value")
    }
    for marker in ["3️⃣", "4️⃣"] {
      let replacement = try unwrap(await forEachReplacementText(in: project, uri: uri, at: positions[marker]))
      XCTAssertTrue(replacement.contains("for element in [1]"), "Statement branch should be convertible")
    }
  }

  func testPreservesMultilineStringIndentation() async throws {
    let (project, uri, positions) = try await makeProject(
      #"""
      let values = [1]
      values.1️⃣forEach { value in
        let text = """
          first
            second
          """
        print(text, value)
      }
      """#
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      #"""
      for value in values {
        let text = """
          first
            second
          """
        print(text, value)
      }
      """#
    )
  }

  func testRejectsCommentsInDiscardedCallSyntax() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach /* after method */ { print($0) }
      array.2️⃣forEach(/* before argument */ { print($0) })
      array.3️⃣forEach { item /* after parameter */ in print(item) }
      """
    )
    for marker in ["1️⃣", "2️⃣", "3️⃣"] {
      let action = try await forEachAction(in: project, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should not discard a comment while converting \(marker)")
    }
  }

  func testRejectsOptionalChainingInSequence() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let arrays: [[Int]]? = [[1, 2]]
      arrays?.1️⃣forEach { print($0) }
      arrays?.joined().2️⃣forEach { print($0) }
      arrays?[0].3️⃣forEach { print($0) }
      """
    )
    for marker in ["1️⃣", "2️⃣", "3️⃣"] {
      let action = try await forEachAction(in: project, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should not convert a call whose receiver uses optional chaining")
    }
  }

  func testAllowsOptionalExpressionInsideSequenceArgument() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      func values(_ count: Int) -> [Int] { Array(0..<count) }
      let optionalCount: Int? = 2
      values(optionalCount ?? 0).1️⃣forEach { print($0) }
      """
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for element in values(optionalCount ?? 0) {\n  print(element)\n}")
  }

  func testRejectsClosureWithAwait() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
        await print(item)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action for await expression")
  }

  func testRejectsClosureWithCaptureList() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      let offset = 1
      array.1️⃣forEach { [offset] item in
        print(item + offset)
      }
      """
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action for closures with a capture list")
  }

  func testParenthesizedClosureParameter() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach({ (item) in
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
      array.1️⃣forEach({ (item: Int) in
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

  func testTypedClosureParameterWithExternalLabel() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      [1].1️⃣forEach { (_ item: Int) in print(item) }
      """
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for item: Int in [1] {\n  print(item)\n}")
  }

  func testDollarZeroDoesNotPenetrateNestedClosure() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach {
        let mapped = [$0].map { $0 + 1 }
        print(mapped)
      }
      """
    )
    let replacement = try unwrap(await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"]))
    // The inner `$0` in `map { $0 + 1 }` must remain untouched
    XCTAssertTrue(replacement.contains("$0 + 1"), "Nested closure $0 should not be rewritten")
    XCTAssertTrue(replacement.contains("for element in"), "Outer $0 should become 'element'")
  }

  func testRewritesOuterDollarZeroInNestedCaptureInitializer() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach {
        let mapped = [1].map { [value = $0] in value + $0 }
        print(mapped)
      }
      """
    )
    let replacement = try unwrap(await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"]))
    XCTAssertTrue(replacement.contains("[value = element]"), "Capture initializer should refer to the outer element")
    XCTAssertTrue(replacement.contains("value + $0"), "Nested closure body should keep its own shorthand parameter")
  }

  func testGeneratedNameAvoidsEscapedIdentifier() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      let `element` = 100
      array.1️⃣forEach { print(`element` + $0) }
      """
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for element1 in array {\n  print(`element` + element1)\n}")
  }

  func testEscapedNamedClosureParameter() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { `class` in print(`class`) }
      """
    )
    let replacement = try await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for `class` in array {\n  print(`class`)\n}")
  }

  func testBareReturnRewrittenToContinueInOutput() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
        if item < 2 {
          return
        }
        print(item)
      }
      """
    )
    let replacement = try unwrap(await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"]))
    XCTAssertTrue(replacement.contains("continue"), "Bare return should become continue")
    XCTAssertFalse(replacement.contains("return"), "No return should remain in the output")
    XCTAssertFalse(replacement.contains("forEachLoop:"), "Simple bare return should not add a loop label")
    XCTAssertFalse(
      replacement.contains("continue forEachLoop"),
      "Simple bare return should stay a plain continue"
    )
  }

  func testPreservesCommentOnRewrittenBareReturn() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
        if item < 2 {
          return /* keep plain return comment */
        }
        print(item)
      }
      """
    )
    let replacement = try unwrap(await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"]))
    XCTAssertTrue(replacement.contains("continue /* keep plain return comment */"))
  }

  func testPreservesCommentOnLabeledContinue() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [[1, 2], [3, 4]]
      array.1️⃣forEach { item in
        for value in item {
          if value < 2 {
            return /* keep nested return comment */
          }
        }
        print(item)
      }
      """
    )
    let replacement = try unwrap(await forEachReplacementText(in: project, uri: uri, at: positions["1️⃣"]))
    XCTAssertTrue(replacement.contains("forEachLoop: for item in array"))
    XCTAssertTrue(replacement.contains("continue forEachLoop /* keep nested return comment */"))
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

    // Ranges that include `forEach` token exactly should offer the action.
    let action33 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["3️⃣"]..<positions["3️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action33, "Cursor on forEach should offer the action")

    let action34 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["3️⃣"]..<positions["4️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action34, "Selection spanning exactly forEach should offer the action")

    // Ranges wider than `forEach` should NOT offer the action.
    let action24 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["2️⃣"]..<positions["4️⃣"],
      context: .init()
    )
    XCTAssertNil(action24, "Selection starting before forEach should not offer the action")

    let action25 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["2️⃣"]..<positions["5️⃣"],
      context: .init()
    )
    XCTAssertNil(action25, "Selection from before forEach to after closure should not offer the action")

    let action35 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["3️⃣"]..<positions["5️⃣"],
      context: .init()
    )
    XCTAssertNil(action35, "Selection from forEach to end of closure should not offer the action")

    let action16 = try await forEachAction(
      in: project,
      uri: uri,
      range: positions["1️⃣"]..<positions["6️⃣"],
      context: .init()
    )
    XCTAssertNil(action16, "Selection spanning entire function should not offer the action")
  }

  func testCursorInfoIsDeferredUntilResolve() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach2️⃣ { item in
        print(item)
      }
      """
    )
    let swiftService = try await unwrap(project.testClient.primaryLanguageService(for: uri) as? SwiftLanguageService)
    let testClient = project.testClient
    let requests = ThreadSafeBox<[String]>(initialValue: [])

    try await swiftService.sourcekitd.withPreRequestHandlingHook {
      let response = try await testClient.send(
        CodeActionRequest(
          range: positions["1️⃣"]..<positions["2️⃣"],
          // Exclude semantic refactorings to observe only this syntax action's cursor-info requests.
          context: .init(only: [.quickFix]),
          textDocument: TextDocumentIdentifier(uri)
        )
      )
      guard case .codeActions(let actions) = response else {
        XCTFail("Expected code actions response")
        return
      }
      let action = try unwrap(actions.first { $0.title == "Convert to 'for-in' loop" })
      XCTAssertNil(action.edit)
      XCTAssertNotNil(action.data)
      XCTAssertEqual(requests.value.count, 0)

      let resolved = try await testClient.send(CodeActionResolveRequest(codeAction: action))
      XCTAssertEqual(resolved.edit?.changes?[uri]?.first?.newText, "for item in array {\n  print(item)\n}")
    } hook: { request in
      let description = request.description.replacing(#"\\"#, with: #"\"#)
      if description.contains("source.request.cursorinfo"), description.contains(uri.sourcekitdSourceFile) {
        requests.withLock { $0.append(description) }
      }
    }

    XCTAssertEqual(requests.value.count, 1)
    let request = try unwrap(requests.value.first)
    assertContains(request, "key.offset: 28,")
  }

  func testDoesNotOfferActionWithoutResolveSupport() async throws {
    let (project, uri, positions) = try await makeProject(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
        print(item)
      }
      """,
      supportsResolve: false
    )
    let action = try await forEachAction(in: project, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action)
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
