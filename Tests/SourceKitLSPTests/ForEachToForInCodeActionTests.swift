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

  private func openDocument(
    _ source: String,
    supportsResolve: Bool = true
  ) async throws -> (TestSourceKitLSPClient, DocumentURI, DocumentPositions) {
    var capabilities = clientCapabilitiesWithCodeActionSupport
    if !supportsResolve {
      capabilities.textDocument?.codeAction?.resolveSupport = nil
    }
    let testClient = try await TestSourceKitLSPClient(capabilities: capabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(source, uri: uri)
    return (testClient, uri, positions)
  }

  private func forEachAction(
    in testClient: TestSourceKitLSPClient,
    uri: DocumentURI,
    at position: Position
  ) async throws -> CodeAction? {
    try await forEachAction(in: testClient, uri: uri, range: position..<position, context: .init())
  }

  private func forEachAction(
    in testClient: TestSourceKitLSPClient,
    uri: DocumentURI,
    range: Range<Position>,
    context: CodeActionContext
  ) async throws -> CodeAction? {
    let result = try await testClient.send(
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
    in testClient: TestSourceKitLSPClient,
    uri: DocumentURI,
    at position: Position
  ) async throws -> String? {
    let action = try unwrap(await forEachAction(in: testClient, uri: uri, at: position))
    let resolved = try await testClient.send(CodeActionResolveRequest(codeAction: action))
    return resolved.edit?.changes?[uri]?.first?.newText
  }

  func testBasicForEachToForInConversion() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
        print(item)
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
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
    let (testClient, uri, positions) = try await openDocument(
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
    let action = try unwrap(await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"]))
    XCTAssertNil(action.edit)
    XCTAssertNotNil(action.data)
    await assertThrowsError(try await testClient.send(CodeActionResolveRequest(codeAction: action))) { error in
      assertContains(
        (error as? ResponseError)?.message ?? "",
        "Only the Swift standard library's forEach can be converted"
      )
    }
  }

  func testRejectsCustomForEachOnSequenceConformance() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      struct CustomSequence: Sequence {
        func makeIterator() -> IndexingIterator<[Int]> {
          [1].makeIterator()
        }
        func forEach(_ body: (Int) throws -> Void) rethrows {
          try body(42)
          try body(42)
        }
      }
      CustomSequence().1️⃣forEach { print($0) }
      """
    )
    let action = try unwrap(await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"]))
    await assertThrowsError(try await testClient.send(CodeActionResolveRequest(codeAction: action))) { error in
      assertContains(
        (error as? ResponseError)?.message ?? "",
        "Only the Swift standard library's forEach can be converted"
      )
    }
  }

  func testConvertsStandardLibraryForEachOnDifferentSequences() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      struct CustomSequence: Sequence {
        func makeIterator() -> IndexingIterator<[Int]> {
          [1].makeIterator()
        }
      }
      func run<S: Sequence>(_ sequence: S) {
        sequence.1️⃣forEach { print($0) }
      }
      (0..<3).2️⃣forEach { print($0) }
      Set([1, 2]).3️⃣forEach { print($0) }
      CustomSequence().4️⃣forEach { print($0) }
      """
    )
    for (marker, sequence) in [
      ("1️⃣", "sequence"),
      ("2️⃣", "(0..<3)"),
      ("3️⃣", "Set([1, 2])"),
      ("4️⃣", "CustomSequence()"),
    ] {
      let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions[marker])
      XCTAssertEqual(replacement, "for element in \(sequence) { print(element) }")
    }
  }

  func testExplicitClosureArgument() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach({ item in
        print(item)
      })
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
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
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { print($0) }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for element in array { print(element) }")
  }

  func testRejectsReturnWithValue() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
    let action = try await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action when closure has return with value")
  }

  func testTransformsBareReturnToContinue() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for item in array {
        if item < 2 {
          continue
        }
        print(item)
      }
      """
    )
  }

  func testTransformsNestedLoopBareReturnToLabeledContinue() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      LOOP: for item in array {
        for value in item {
          if value < 2 {
            continue LOOP
          }
        }
        print(item)
      }
      """
    )
  }

  func testAllowsTryInClosure() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
    let action = try unwrap(await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"]))
    let resolved = try await testClient.send(CodeActionResolveRequest(codeAction: action))
    let edit = try unwrap(resolved.edit?.changes?[uri]?.first)
    XCTAssertEqual(edit.range.lowerBound, positions["2️⃣"], "The edit must also remove the original try")
    XCTAssertEqual(
      edit.newText,
      """
      for item in try array {
          try check(item)
        }
      """
    )
  }

  func testMovesOuterTryToThrowingSequence() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      func makeArray() throws -> [Int] { [1, 2, 3] }
      func run() throws {
        2️⃣try makeArray().1️⃣forEach { print($0) }
      }
      """
    )
    let action = try unwrap(await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"]))
    let resolved = try await testClient.send(CodeActionResolveRequest(codeAction: action))
    let edit = try unwrap(resolved.edit?.changes?[uri]?.first)
    XCTAssertEqual(edit.range.lowerBound, positions["2️⃣"], "The edit must also remove the original try")
    XCTAssertEqual(edit.newText, "for element in try makeArray() { print(element) }")
  }

  func testRejectsTryOptionalAndForcedCalls() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
      let action = try await forEachAction(in: testClient, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should not offer an action for \(marker) because the outer try changes error handling")
    }
  }

  func testRejectsCallsUsedAsExpressions() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      func consume(_ value: Void) {}
      func run() {
        let array = [1, 2, 3]
        let result: Void = array.1️⃣forEach { print($0) }
        consume(array.2️⃣forEach { print($0) })
        consume(result)
      }
      func explicitlyReturningVoid() -> Void {
        return [1].3️⃣forEach { print($0) }
      }
      """
    )
    for marker in ["1️⃣", "2️⃣", "3️⃣"] {
      let action = try await forEachAction(in: testClient, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should only offer an action for a standalone forEach statement")
    }
  }

  func testAllowsSoleExpressionInVoidContexts() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      import Dispatch
      let array = [1]
      let matrix = [[1]]
      func runVoid() { [1].1️⃣forEach { print($0) } }
      let voidCallback = { () -> Void in [1].2️⃣forEach { print($0) } }
      let inferredCallback = { [1].3️⃣forEach { print($0) } }
      Task { array.4️⃣forEach { print($0) } }
      DispatchQueue.main.async { array.5️⃣forEach { print($0) } }
      matrix.forEach { row in
        6️⃣row.7️⃣forEach { print($0) }8️⃣
      }
      """
    )
    for (marker, sequence) in [
      ("1️⃣", "[1]"), ("2️⃣", "[1]"), ("3️⃣", "[1]"),
      ("4️⃣", "array"), ("5️⃣", "array"), ("7️⃣", "row"),
    ] {
      let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions[marker])
      XCTAssertEqual(replacement, "for element in \(sequence) { print(element) }")
    }
    let innerAction = try unwrap(await forEachAction(in: testClient, uri: uri, at: positions["7️⃣"]))
    let resolved = try await testClient.send(CodeActionResolveRequest(codeAction: innerAction))
    let edits = try unwrap(resolved.edit?.changes?[uri])
    XCTAssertEqual(edits.count, 1)
    let edit = try unwrap(edits.first)
    XCTAssertEqual(edit.range, positions["6️⃣"]..<positions["8️⃣"])
    XCTAssertEqual(edit.newText, "for element in row { print(element) }")
  }

  func testAllowsIfAndSwitchStatementBranches() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      func statements(_ flag: Bool, _ number: Int) {
        if flag {
          [1].1️⃣forEach { print($0) }
        }
        switch number {
        case 0:
          [1].2️⃣forEach { print($0) }
        default:
          break
        }
      }
      """
    )
    for marker in ["1️⃣", "2️⃣"] {
      let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions[marker])
      XCTAssertEqual(replacement, "for element in [1] { print(element) }")
    }
  }

  func testPreservesMultilineStringIndentation() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
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

  func testAllowsCommentsInDiscardedCallSyntax() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach /* after method */ { print($0) }
      array.2️⃣forEach(/* before argument */ { print($0) })
      array.3️⃣forEach { item /* after parameter */ in print(item) }
      """
    )
    for (marker, parameter) in [("1️⃣", "element"), ("2️⃣", "element"), ("3️⃣", "item")] {
      let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions[marker])
      XCTAssertEqual(replacement, "for \(parameter) in array { print(\(parameter)) }")
    }
  }

  func testRejectsOptionalChainingInSequence() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let arrays: [[Int]]? = [[1, 2]]
      arrays?.1️⃣forEach { print($0) }
      arrays?.joined().2️⃣forEach { print($0) }
      arrays?[0].3️⃣forEach { print($0) }
      """
    )
    for marker in ["1️⃣", "2️⃣", "3️⃣"] {
      let action = try await forEachAction(in: testClient, uri: uri, at: positions[marker])
      XCTAssertNil(action, "Should not convert a call whose receiver uses optional chaining")
    }
  }

  func testAllowsOptionalExpressionInsideSequenceArgument() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      func values(_ count: Int) -> [Int] { Array(0..<count) }
      let optionalCount: Int? = 2
      values(optionalCount ?? 0).1️⃣forEach { print($0) }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for element in values(optionalCount ?? 0) { print(element) }")
  }

  func testRejectsClosureWithAwait() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
        await print(item)
      }
      """
    )
    let action = try await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action for await expression")
  }

  func testRejectsClosureWithCaptureList() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      let offset = 1
      array.1️⃣forEach { [offset] item in
        print(item + offset)
      }
      """
    )
    let action = try await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action, "Should NOT offer action for closures with a capture list")
  }

  func testParenthesizedClosureParameter() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach({ (item) in
        print(item)
      })
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
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
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach({ (item: Int) in
        print(item)
      })
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
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
    let (testClient, uri, positions) = try await openDocument(
      """
      [1].1️⃣forEach { (_ item: Int) in print(item) }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for item: Int in [1] { print(item) }")
  }

  func testDollarZeroDoesNotPenetrateNestedClosure() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach {
        let mapped = [$0].map { $0 + 1 }
        print(mapped)
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for element in array {
        let mapped = [element].map { $0 + 1 }
        print(mapped)
      }
      """
    )
  }

  func testRewritesOuterDollarZeroInNestedCaptureInitializer() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach {
        let mapped = [1].map { [value = $0] in value + $0 }
        print(mapped)
      }
      """
    )
    let replacement = try unwrap(await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"]))
    XCTAssertTrue(replacement.contains("[value = element]"), "Capture initializer should refer to the outer element")
    XCTAssertTrue(replacement.contains("value + $0"), "Nested closure body should keep its own shorthand parameter")
  }

  func testGeneratedNameAvoidsEscapedIdentifier() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      let `element` = 100
      array.1️⃣forEach { print(`element` + $0) }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for element1 in array { print(`element` + element1) }")
  }

  func testEscapedNamedClosureParameter() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { `class` in print(`class`) }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(replacement, "for `class` in array { print(`class`) }")
  }

  func testPreservesCommentOnRewrittenBareReturn() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
    let replacement = try unwrap(await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"]))
    XCTAssertTrue(replacement.contains("continue /* keep plain return comment */"))
  }

  func testPreservesCommentOnLabeledContinue() async throws {
    let (testClient, uri, positions) = try await openDocument(
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
    let replacement = try unwrap(await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"]))
    XCTAssertTrue(replacement.contains("LOOP: for item in array"))
    XCTAssertTrue(replacement.contains("continue LOOP /* keep nested return comment */"))
  }

  func testSelectionRangeBoundaries() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      1️⃣func test() {
        let array = [1, 2, 3]
        2️⃣array.reversed().3️⃣forEach4️⃣ { item in
          print(item)
        }5️⃣
      }6️⃣
      """
    )

    for (start, end) in [("3️⃣", "3️⃣"), ("3️⃣", "4️⃣"), ("2️⃣", "4️⃣"), ("2️⃣", "5️⃣"), ("3️⃣", "5️⃣")] {
      let action = try await forEachAction(
        in: testClient,
        uri: uri,
        range: positions[start]..<positions[end],
        context: .init()
      )
      XCTAssertNotNil(action, "Selection inside the forEach call should offer the action")
    }

    for (start, end) in [("1️⃣", "6️⃣"), ("1️⃣", "4️⃣"), ("2️⃣", "6️⃣")] {
      let action = try await forEachAction(
        in: testClient,
        uri: uri,
        range: positions[start]..<positions[end],
        context: .init()
      )
      XCTAssertNil(action, "Selection extending outside the forEach call should not offer the action")
    }
  }

  func testCursorInfoIsDeferredUntilResolve() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach2️⃣ { item in
        print(item)
      }
      """
    )
    let swiftService = try await unwrap(testClient.primaryLanguageService(for: uri) as? SwiftLanguageService)
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
      XCTAssertEqual(
        resolved.edit?.changes?[uri]?.first?.newText,
        """
        for item in array {
          print(item)
        }
        """
      )
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
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      array.1️⃣forEach { item in
        print(item)
      }
      """,
      supportsResolve: false
    )
    let action = try await forEachAction(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertNil(action)
  }

  func testOffersActionInsideReceiverParameterAndBody() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.reversed().forEach { 2️⃣item in
        3️⃣print(4️⃣item5️⃣)
      }
      """
    )

    for marker in ["1️⃣", "2️⃣", "3️⃣", "4️⃣"] {
      let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions[marker])
      XCTAssertEqual(
        replacement,
        """
        for item in array.reversed() {
          print(item)
        }
        """
      )
    }
    let action = try await forEachAction(
      in: testClient,
      uri: uri,
      range: positions["4️⃣"]..<positions["5️⃣"],
      context: .init()
    )
    XCTAssertNotNil(action, "Selection inside the body should find the enclosing forEach call")
  }

  func testDoesNotSelectOuterForEachAcrossLocalScope() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      [1].forEach { item in
        func local() { 1️⃣print(item) }
        var computed: Int {
          2️⃣print(item)
          return item
        }
        local()
        print(computed)
      }
      """
    )
    for marker in ["1️⃣", "2️⃣"] {
      let action = try await forEachAction(in: testClient, uri: uri, at: positions[marker])
      XCTAssertNil(action, "The search should not cross a local function or getter scope")
    }
  }

  func testDoesNotFallBackFromUnsupportedInnerForEach() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      func check(_ value: Int) throws {}
      [[1]].forEach { row in
        row.1️⃣forEach { return 42 }
        row.2️⃣forEach { [row] value in print(row, value) }
        try? row.3️⃣forEach { try check($0) }
        let optionalRow: [Int]? = row
        optionalRow?.4️⃣forEach { print($0) }
      }
      """
    )
    for marker in ["1️⃣", "2️⃣", "3️⃣", "4️⃣"] {
      let action = try await forEachAction(in: testClient, uri: uri, at: positions[marker])
      XCTAssertNil(action, "An unsupported inner forEach should not select the outer forEach")
    }
  }

  func testPreservesReturnsInNestedClosureAndFunction() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      [1].forEach { item in
        let mapped = [item].1️⃣map { return $0 + 1 }
        let callback = { () -> Void in return }
        func local() { return }
        print(mapped)
        callback()
        local()
        return
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for item in [1] {
        let mapped = [item].map { return $0 + 1 }
        let callback = { () -> Void in return }
        func local() { return }
        print(mapped)
        callback()
        local()
        continue
      }
      """
    )
  }

  func testRewritesDollarZeroInLocalVariableInitializer() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      [1].1️⃣forEach {
        let value = $0
        let callback = { [captured = $0] in print(captured) }
        print(value)
        callback()
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for element in [1] {
        let value = element
        let callback = { [captured = element] in print(captured) }
        print(value)
        callback()
      }
      """
    )
  }

  func testPreservesUnusualBodyFormatting() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      [1].1️⃣forEach { value in
           if value > 0 {  print(value)  }
        print(  value  )
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for value in [1] {
           if value > 0 {  print(value)  }
        print(  value  )
      }
      """
    )
  }

  func testPreservesTabIndentation() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      [1].1️⃣forEach { value in
      \tprint(value)
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      for value in [1] {
      \tprint(value)
      }
      """
    )
  }

  func testRewritesConditionalCompilationBlocks() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      [[1]].1️⃣forEach {
        #if true
        let values = $0
        for value in values {
          if value > 0 { return }
        }
        #else
        print($0)
        return
        #endif
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      LOOP: for element in [[1]] {
        #if true
        let values = element
        for value in values {
          if value > 0 { continue LOOP }
        }
        #else
        print(element)
        continue
        #endif
      }
      """
    )
  }

  func testGeneratedLoopLabelAvoidsExistingLabel() async throws {
    let (testClient, uri, positions) = try await openDocument(
      """
      [[1]].1️⃣forEach { values in
        LOOP: for value in values {
          if value > 0 { return }
          break LOOP
        }
      }
      """
    )
    let replacement = try await forEachReplacementText(in: testClient, uri: uri, at: positions["1️⃣"])
    XCTAssertEqual(
      replacement,
      """
      LOOP1: for values in [[1]] {
        LOOP: for value in values {
          if value > 0 { continue LOOP1 }
          break LOOP
        }
      }
      """
    )
  }

}
