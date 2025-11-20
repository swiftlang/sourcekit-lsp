//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring
import Csourcekitd
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitD
import SwiftExtensions
import ToolchainRegistry
import XCTest

final class SwiftSourceKitPluginTests: SourceKitLSPTestCase {
  /// Returns a path to a file name that is unique to this test execution.
  ///
  /// The file does not actually exist on disk.
  private func scratchFilePath(testName: String = #function, fileName: String = "a.swift") -> String {
    #if os(Windows)
    return "C:\\\(testScratchName(testName: testName))\\\(fileName)"
    #else
    return "/\(testScratchName(testName: testName))/\(fileName)"
    #endif
  }

  func getSourceKitD() async throws -> SourceKitD {
    guard let sourcekitd = await ToolchainRegistry.forTesting.default?.sourcekitd else {
      struct NoSourceKitdFound: Error, CustomStringConvertible {
        var description: String = "Could not find SourceKitD"
      }
      throw NoSourceKitdFound()
    }
    return try await SourceKitD.getOrCreate(
      dylibPath: sourcekitd,
      pluginPaths: try sourceKitPluginPaths
    )
  }

  func testBasicCompletion() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    try await SkipUnless.sourcekitdSupportsFullDocumentationInCompletion()

    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func test() {
            self.1️⃣ 2️⃣
          }
        }
        """,
      compilerArguments: [path]
    )

    await assertThrowsError(
      try await sourcekitd.completeUpdate(path: path, position: positions["1️⃣"], filter: ""),
      expectedMessage: #/no matching session/#
    )

    await assertThrowsError(
      try await sourcekitd.completeClose(path: path, position: positions["1️⃣"]),
      expectedMessage: #/no matching session/#
    )

    func checkTestMethod(result: CompletionResultSet, file: StaticString = #filePath, line: UInt = #line) {
      guard let test = result.items.first(where: { $0.name == "test()" }) else {
        XCTFail("did not find test(); got \(result.items)", file: file, line: line)
        return
      }
      XCTAssertEqual(test.kind, sourcekitd.values.declMethodInstance, file: file, line: line)
      XCTAssertEqual(test.description, "test()", file: file, line: line)
      XCTAssertEqual(test.sourcetext, "test()", file: file, line: line)
      XCTAssertEqual(test.typename, "Void", file: file, line: line)
      XCTAssertEqual(test.priorityBucket, 9, file: file, line: line)
      XCTAssertFalse(test.semanticScore.isNaN, file: file, line: line)
      XCTAssertEqual(test.isSystem, false, file: file, line: line)
      XCTAssertEqual(test.numBytesToErase, 0, file: file, line: line)
      XCTAssertEqual(test.hasDiagnostic, false, file: file, line: line)
    }

    func checkTestMethodAnnotated(result: CompletionResultSet, file: StaticString = #filePath, line: UInt = #line) {
      guard let test = result.items.first(where: { $0.name == "test()" }) else {
        XCTFail("did not find test(); got \(result.items)", file: file, line: line)
        return
      }
      XCTAssertEqual(test.kind, sourcekitd.values.declMethodInstance, file: file, line: line)
      XCTAssertEqual(test.description, "<name>test</name>()", file: file, line: line)
      XCTAssertEqual(test.sourcetext, "test()", file: file, line: line)
      XCTAssertEqual(test.typename, "<typeid.sys>Void</typeid.sys>", file: file, line: line)
      XCTAssertEqual(test.priorityBucket, 9, file: file, line: line)
      XCTAssertFalse(test.semanticScore.isNaN, file: file, line: line)
      XCTAssertEqual(test.isSystem, false, file: file, line: line)
      XCTAssertEqual(test.numBytesToErase, 0, file: file, line: line)
      XCTAssertEqual(test.hasDiagnostic, false, file: file, line: line)
    }

    var unfilteredResultCount: Int? = nil

    let result1 = try await sourcekitd.completeOpen(path: path, position: positions["1️⃣"], filter: "")
    XCTAssertEqual(result1.items.count, result1.unfilteredResultCount)
    checkTestMethod(result: result1)
    unfilteredResultCount = result1.unfilteredResultCount

    let result2 = try await sourcekitd.completeUpdate(path: path, position: positions["1️⃣"], filter: "")
    XCTAssertEqual(result2.items.count, result2.unfilteredResultCount)
    XCTAssertEqual(result2.unfilteredResultCount, unfilteredResultCount)
    checkTestMethod(result: result2)

    let result3 = try await sourcekitd.completeUpdate(path: path, position: positions["1️⃣"], filter: "test")
    XCTAssertEqual(result3.unfilteredResultCount, unfilteredResultCount)
    XCTAssertEqual(result3.items.count, 1)
    checkTestMethod(result: result3)

    let result4 = try await sourcekitd.completeUpdate(path: path, position: positions["1️⃣"], filter: "testify")
    XCTAssertEqual(result4.unfilteredResultCount, unfilteredResultCount)
    XCTAssertEqual(result4.items.count, 0)

    // Update on different location
    await assertThrowsError(
      try await sourcekitd.completeUpdate(path: path, position: positions["2️⃣"], filter: ""),
      expectedMessage: #/no matching session/#
    )
    await assertThrowsError(
      try await sourcekitd.completeClose(path: path, position: positions["2️⃣"]),
      expectedMessage: #/no matching session/#
    )

    // Update on different location
    await assertThrowsError(
      try await sourcekitd.completeUpdate(path: "/other.swift", position: positions["1️⃣"], filter: ""),
      expectedMessage: #/no matching session/#
    )

    // Annotated
    let result5 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      flags: [.annotate]
    )
    XCTAssertEqual(result5.items.count, result5.unfilteredResultCount)
    checkTestMethodAnnotated(result: result5)

    let result6 = try await sourcekitd.completeUpdate(
      path: path,
      position: positions["1️⃣"],
      filter: "test",
      flags: [.annotate]
    )
    XCTAssertEqual(result6.items.count, 1)
    checkTestMethodAnnotated(result: result6)

    try await sourcekitd.completeClose(path: path, position: positions["1️⃣"])

    await assertThrowsError(
      try await sourcekitd.completeUpdate(path: path, position: positions["1️⃣"], filter: ""),
      expectedMessage: #/no matching session/#
    )
  }

  func testEmptyName() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        func test1(closure: () -> Void) {
          closure(1️⃣
        }
        func noArg() -> String {}
        func noArg() -> Int {}
        func test2() {
          noArg(2️⃣
        }
        """,
      compilerArguments: [path]
    )
    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      flags: [.annotate]
    )
    XCTAssertEqual(result1.items.count, 1)
    XCTAssertEqual(result1.items[0].name, "")

    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["2️⃣"],
      filter: "",
      flags: [.annotate],
      maxResults: 1
    )
    XCTAssertEqual(result2.items.count, 1)
    XCTAssertEqual(result2.items[0].name, "")
    let doc = try await sourcekitd.completeDocumentation(id: result2.items[0].id)
    XCTAssertNil(doc.docComment)
    XCTAssertNil(doc.docFullAsXML)
    XCTAssertNil(doc.docBrief)
  }

  func testMultipleFiles() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let pathA = scratchFilePath(fileName: "a.swift")
    let pathB = scratchFilePath(fileName: "b.swift")
    let positionsA = try await sourcekitd.openDocument(
      pathA,
      contents: """
        struct A {
          func aaa(b: B) {
            b.1️⃣
          }
        }
        """,
      compilerArguments: [pathA, pathB]
    )
    let positionsB = try await sourcekitd.openDocument(
      pathB,
      contents: """
        struct B {
          func bbb(a: A) {
            a.2️⃣
          }
        }
        """,
      compilerArguments: [pathA, pathB]
    )

    func checkResult(name: String, result: CompletionResultSet, file: StaticString = #filePath, line: UInt = #line) {
      guard let test = result.items.first(where: { $0.name == name }) else {
        XCTFail("did not find \(name); got \(result.items)", file: file, line: line)
        return
      }
      XCTAssertEqual(test.kind, sourcekitd.values.declMethodInstance, file: file, line: line)
    }

    let result1 = try await sourcekitd.completeOpen(
      path: pathA,
      position: positionsA["1️⃣"],
      filter: ""
    )
    checkResult(name: "bbb(a:)", result: result1)

    let result2 = try await sourcekitd.completeUpdate(
      path: pathA,
      position: positionsA["1️⃣"],
      filter: "b"
    )
    checkResult(name: "bbb(a:)", result: result2)

    let result3 = try await sourcekitd.completeOpen(
      path: pathB,
      position: positionsB["2️⃣"],
      filter: ""
    )
    checkResult(name: "aaa(b:)", result: result3)

    let result4 = try await sourcekitd.completeUpdate(
      path: pathB,
      position: positionsB["2️⃣"],
      filter: "a"
    )
    checkResult(name: "aaa(b:)", result: result4)
  }

  func testCancellation() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct A: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }
        struct B: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }
        struct C: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }

        func + (lhs: A, rhs: B) -> A { fatalError() }
        func + (lhs: B, rhs: C) -> A { fatalError() }
        func + (lhs: C, rhs: A) -> A { fatalError() }

        func + (lhs: B, rhs: A) -> B { fatalError() }
        func + (lhs: C, rhs: B) -> B { fatalError() }
        func + (lhs: A, rhs: C) -> B { fatalError() }

        func + (lhs: C, rhs: B) -> C { fatalError() }
        func + (lhs: B, rhs: C) -> C { fatalError() }
        func + (lhs: A, rhs: A) -> C { fatalError() }

        class Foo {
          func slow(x: Invalid1, y: Invalid2) {
            let x: C = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 1️⃣
          }

          struct Foo {
            let fooMember: String
          }

          func fast(a: Foo) {
            a.2️⃣
          }
        }
        """,
      compilerArguments: [path]
    )

    let slowCompletionRequestSent = self.expectation(description: "slow completion result sent")
    let slowCompletionResultReceived = self.expectation(description: "slow completion")
    try await sourcekitd.withRequestHandlingHook {
      let slowCompletionTask = Task {
        await assertThrowsError(try await sourcekitd.completeOpen(path: path, position: positions["1️⃣"], filter: "")) {
          XCTAssert($0 is CancellationError, "Expected completion to be cancelled, failed with \($0)")
        }
        slowCompletionResultReceived.fulfill()
      }
      // Wait for the slow completion request to actually be sent to sourcekitd. Otherwise, we might hit a cancellation
      // check somewhere during request sending and we aren't actually sending the completion request to sourcekitd.
      try await fulfillmentOfOrThrow(slowCompletionRequestSent)

      slowCompletionTask.cancel()
      try await fulfillmentOfOrThrow(slowCompletionResultReceived, timeout: 30)
    } hook: { request in
      // Check that we aren't matching against a request sent by something else that has handle to the same sourcekitd.
      assertContains(request.description.replacing(#"\\"#, with: #"\"#), path)
      slowCompletionRequestSent.fulfill()
    }

    let fastCompletionStarted = Date()
    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["2️⃣"],
      filter: ""
    )
    XCTAssert(result.items.count > 0)
    XCTAssertLessThan(Date().timeIntervalSince(fastCompletionStarted), 30)
  }

  func testEdits() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func test() {
            let solf = 1
            solo.1️⃣
          }
          func magic_method_of_greatness() {}
        }
        """,
      compilerArguments: [path]
    )

    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "magic_method_of_greatness",
      flags: []
    )
    XCTAssertEqual(result1.unfilteredResultCount, 0)
    XCTAssertEqual(result1.items.count, 0)

    let sOffset = """
      struct S {
        func test() {
          let solo = 1
          s
      """.count - 1

    try await sourcekitd.editDocument(path, fromOffset: sOffset + 1, length: 1, newContents: "e")
    try await sourcekitd.editDocument(path, fromOffset: sOffset + 3, length: 1, newContents: "f")

    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "magic_method_of_greatness",
      flags: []
    )
    XCTAssertGreaterThan(result2.unfilteredResultCount, 1)
    XCTAssertEqual(result2.items.count, 1)

    try await sourcekitd.editDocument(path, fromOffset: sOffset, length: 3, newContents: "")
    try await sourcekitd.editDocument(path, fromOffset: sOffset, length: 0, newContents: "sel")

    let result3 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "magic_method_of_greatness",
      flags: []
    )
    XCTAssertGreaterThan(result3.unfilteredResultCount, 1)
    XCTAssertEqual(result3.items.count, 1)
  }

  func testEditBounds() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    _ = try await sourcekitd.openDocument(
      path,
      contents: "",
      compilerArguments: [path]
    )

    let typeWithMethod = """
      struct S {
        static func foo() -> Int {}
      }

      """
    var fullText = typeWithMethod

    try await sourcekitd.editDocument(path, fromOffset: 0, length: 0, newContents: typeWithMethod)

    let completion = """
      S.
      """
    fullText += completion

    try await sourcekitd.editDocument(path, fromOffset: typeWithMethod.utf8.count, length: 0, newContents: completion)

    func testCompletion(file: StaticString = #filePath, line: UInt = #line) async throws {
      let result = try await sourcekitd.completeOpen(
        path: path,
        position: Position(line: 3, utf16index: 2),
        filter: "foo",
        flags: []
      )
      XCTAssertGreaterThan(result.unfilteredResultCount, 1, file: file, line: line)
      XCTAssertEqual(result.items.count, 1, file: file, line: line)
    }
    try await testCompletion()

    // Bogus edits are ignored (negative offsets crash SourceKit itself so we don't test them here).
    await assertThrowsError(
      try await sourcekitd.editDocument(path, fromOffset: 0, length: 99999, newContents: "")
    )
    await assertThrowsError(
      try await sourcekitd.editDocument(path, fromOffset: 99999, length: 1, newContents: "")
    )
    await assertThrowsError(
      try await sourcekitd.editDocument(path, fromOffset: 99999, length: 0, newContents: "unrelated")
    )
    // SourceKit doesn't throw an error for a no-op edit.
    try await sourcekitd.editDocument(path, fromOffset: 99999, length: 0, newContents: "")

    try await sourcekitd.editDocument(path, fromOffset: 0, length: 0, newContents: "")
    try await sourcekitd.editDocument(path, fromOffset: fullText.utf8.count, length: 0, newContents: "")

    try await testCompletion()

    let badCompletion = """
      X.
      """
    fullText = fullText.dropLast(2) + badCompletion

    try await sourcekitd.editDocument(path, fromOffset: fullText.utf8.count - 2, length: 2, newContents: badCompletion)

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: Position(line: 3, utf16index: 2),
      filter: "foo",
      flags: []
    )
    XCTAssertEqual(result.unfilteredResultCount, 0)
    XCTAssertEqual(result.items.count, 0)
  }

  func testDocumentation() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    try await SkipUnless.sourcekitdSupportsFullDocumentationInCompletion()

    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        protocol P {
          /// Protocol P foo1
          func foo1()
        }
        struct S: P {
          func foo1() {}
          /// Struct S foo2
          func foo2() {}
          func foo3() {}
          func test() {
            self.1️⃣
          }
        }
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "foo"
    )
    XCTAssertGreaterThan(result.unfilteredResultCount, 3)
    let sym1 = try unwrap(result.items.first(where: { $0.name == "foo1()" }), "did not find foo1; got \(result.items)")
    let sym2 = try unwrap(result.items.first(where: { $0.name == "foo2()" }), "did not find foo2; got \(result.items)")
    let sym3 = try unwrap(result.items.first(where: { $0.name == "foo3()" }), "did not find foo3; got \(result.items)")

    let sym1Doc = try await sourcekitd.completeDocumentation(id: sym1.id)
    XCTAssertEqual(sym1Doc.docComment, "Protocol P foo1")
    XCTAssertEqual(
      sym1Doc.docFullAsXML,
      """
      <Function file="\(path)" line="3" column="8">\
      <Name>foo1()</Name>\
      <USR>s:1a1PP4foo1yyF</USR>\
      <Declaration>func foo1()</Declaration>\
      <CommentParts>\
      <Abstract><Para>Protocol P foo1</Para></Abstract>\
      <Discussion><Note>\
      <Para>This documentation comment was inherited from <codeVoice>P</codeVoice>.</Para>\
      </Note></Discussion>\
      </CommentParts>\
      </Function>
      """
    )
    XCTAssertEqual(sym1Doc.docBrief, "Protocol P foo1")
    XCTAssertEqual(sym1Doc.associatedUSRs, ["s:1a1SV4foo1yyF", "s:1a1PP4foo1yyF"])

    let sym2Doc = try await sourcekitd.completeDocumentation(id: sym2.id)
    XCTAssertEqual(sym2Doc.docComment, "Struct S foo2")
    XCTAssertEqual(
      sym2Doc.docFullAsXML,
      """
      <Function file="\(path)" line="8" column="8">\
      <Name>foo2()</Name>\
      <USR>s:1a1SV4foo2yyF</USR>\
      <Declaration>func foo2()</Declaration>\
      <CommentParts>\
      <Abstract><Para>Struct S foo2</Para></Abstract>\
      </CommentParts>\
      </Function>
      """
    )
    XCTAssertEqual(sym2Doc.docBrief, "Struct S foo2")
    XCTAssertEqual(sym2Doc.associatedUSRs, ["s:1a1SV4foo2yyF"])

    let sym3Doc = try await sourcekitd.completeDocumentation(id: sym3.id)
    XCTAssertNil(sym3Doc.docComment)
    XCTAssertNil(sym3Doc.docFullAsXML)
    XCTAssertNil(sym3Doc.docBrief)
    XCTAssertEqual(sym3Doc.associatedUSRs, ["s:1a1SV4foo3yyF"])
  }

  func testNumBytesToErase() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S { var myVar: Int }
        func test(s: S?) {
          s.1️⃣
        }
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    XCTAssertEqual(result.items.count, result.unfilteredResultCount)
    let myVar = try unwrap(result.items.first(where: { $0.name == "myVar" }), "did not find myVar; got \(result.items)")
    XCTAssertEqual(myVar.isSystem, false)
    XCTAssertEqual(myVar.numBytesToErase, 1)

    let unwrapped = try unwrap(
      result.items.first(where: { $0.name == "unsafelyUnwrapped" }),
      "did not find myVar; got \(result.items)"
    )

    XCTAssertEqual(unwrapped.isSystem, true)
    XCTAssertEqual(unwrapped.numBytesToErase, 0)
  }

  func testObjectLiterals() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        func test() {
        }1️⃣
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    XCTAssertFalse(
      result.items.contains(where: {
        $0.description.hasPrefix("#colorLiteral") || $0.description.hasPrefix("#imageLiteral")
      })
    )
  }

  func testAddInitsToTopLevel() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        func test() {
        1️⃣}
        struct MyStruct {
        init(arg1: Int) {}
        init(arg2: String) {}
        }
        """,
      compilerArguments: [path]
    )

    // With 'addInitsToTopLevel'
    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "MyStr",
      flags: [.addInitsToTopLevel]
    )

    XCTAssert(result1.items.filter({ $0.description.hasPrefix("MyStruct") }).count == 3)
    let typeResult = try unwrap(
      result1.items.first { $0.description == "MyStruct" && $0.kind == sourcekitd.values.declStruct }
    )
    XCTAssertNotNil(typeResult.groupID)
    XCTAssert(
      result1.items.contains(where: {
        $0.description.hasPrefix("MyStruct(arg1:") && $0.kind == sourcekitd.values.declConstructor
          && $0.groupID == typeResult.groupID
      })
    )
    XCTAssert(
      result1.items.contains(where: {
        $0.description.hasPrefix("MyStruct(arg2:") && $0.kind == sourcekitd.values.declConstructor
          && $0.groupID == typeResult.groupID
      })
    )
    XCTAssertLessThan(
      try unwrap(result1.items.firstIndex(where: { $0.description == "MyStruct" })),
      try unwrap(result1.items.firstIndex(where: { $0.description.hasPrefix("MyStruct(") })),
      "Type names must precede the initializer calls"
    )

    // Without 'addInitsToTopLevel'
    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "MyStr",
      flags: []
    )
    XCTAssert(result2.items.filter({ $0.description.hasPrefix("MyStruct") }).count == 1)
    XCTAssertFalse(result2.items.contains(where: { $0.description.hasPrefix("MyStruct(") }))
  }

  func testMembersGroupID() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct Animal {
          var name: String
          var species: String
          func name(changedTo: String) { }
          func name(updatedTo: String) { }
          func otherFunction() { }
        }
        func test() {
          let animal = Animal(name: "", species: "")
          animal.1️⃣
        }
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    guard result.items.count == 6 else {
      XCTFail("Expected 6 completion results; received \(result)")
      return
    }

    // Properties don't have a groupID.
    XCTAssertEqual(result.items[0].name, "name")
    XCTAssertNil(result.items[0].groupID)
    XCTAssertEqual(result.items[1].name, "species")
    XCTAssertNil(result.items[1].groupID)

    XCTAssertEqual(result.items[2].name, "name(changedTo:)")
    XCTAssertEqual(result.items[3].name, "name(updatedTo:)")
    XCTAssertEqual(result.items[2].groupID, result.items[3].groupID)

    XCTAssertEqual(result.items[4].name, "otherFunction()")
    XCTAssertNotNil(result.items[4].groupID)
  }

  func testAddCallWithNoDefaultArgs() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct Defaults {
          func noDefault(a: Int) { }
          func singleDefault(a: Int = 0) { }
        }
        func defaults(def: Defaults) {
          def.1️⃣
        }
        """,
      compilerArguments: [path]
    )

    // With 'addCallWithNoDefaultArgs'
    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      flags: [.addCallWithNoDefaultArgs]
    )
    guard result1.items.count == 4 else {
      XCTFail("Expected 4 results; received \(result1)")
      return
    }
    XCTAssertEqual(result1.items[0].description, "noDefault(a: Int)")
    XCTAssertEqual(result1.items[1].description, "singleDefault()")
    XCTAssertEqual(result1.items[2].description, "singleDefault(a: Int)")
    XCTAssertEqual(result1.items[3].description, "self")

    // Without 'addCallWithNoDefaultArgs'
    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    guard result2.items.count == 3 else {
      XCTFail("Expected 3 results; received \(result2)")
      return
    }
    XCTAssertEqual(result2.items[0].description, "noDefault(a: Int)")
    XCTAssertEqual(result2.items[1].description, "singleDefault(a: Int)")
    XCTAssertEqual(result2.items[2].description, "self")
  }

  func testTextMatchScore() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func goodMatchOne() {}
          func goodMatchNotOneButTwo() {}
          func test() {
            self.1️⃣
          }
        }
        """,
      compilerArguments: [path]
    )

    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "gmo"
    )
    XCTAssertGreaterThan(result1.unfilteredResultCount, result1.items.count)
    guard result1.items.count >= 2 else {
      XCTFail("Expected at least 2 results; received \(result1)")
      return
    }
    XCTAssertEqual(result1.items[0].description, "goodMatchOne()")
    XCTAssertEqual(result1.items[1].description, "goodMatchNotOneButTwo()")
    XCTAssertGreaterThan(result1.items[0].textMatchScore, result1.items[1].textMatchScore)
    let result1Score = result1.items[0].textMatchScore

    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "gmo",
      useXPC: true
    )
    guard result2.items.count >= 2 else {
      XCTFail("Expected at least 2 results; received \(result2)")
      return
    }
    XCTAssertEqual(result2.items[0].description, "goodMatchOne()")
    XCTAssertEqual(result2.items[1].description, "goodMatchNotOneButTwo()")
    XCTAssertGreaterThan(result2.items[0].textMatchScore, result2.items[1].textMatchScore)
    XCTAssertEqual(result2.items[0].textMatchScore, result1Score)
  }

  func testSemanticScore() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func goodMatchAsync() async {}
          @available(*, deprecated)
          func goodMatchDeprecated() {}
          func goodMatchType() {}
          func test() {
            let goodMatchLocal = 1
        1️⃣
          }
        }
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "goodMatch"
    )
    guard result.items.count >= 4 else {
      XCTFail("Expected at least 4 results; received \(result)")
      return
    }
    XCTAssertEqual(result.items[0].description, "goodMatchLocal")
    XCTAssertEqual(result.items[1].description, "goodMatchAsync() async")
    XCTAssertEqual(result.items[2].description, "goodMatchType()")
    XCTAssertEqual(result.items[3].description, "goodMatchDeprecated()")
    XCTAssertGreaterThan(result.items[0].semanticScore, result.items[1].semanticScore)
    // Note: async and deprecated get the same penalty currently, but we don't want to be too specific in this test.
    XCTAssertEqual(result.items[1].semanticScore, result.items[2].semanticScore)
    XCTAssertGreaterThan(result.items[1].semanticScore, result.items[3].semanticScore)
    XCTAssertFalse(result.items[1].hasDiagnostic)
    XCTAssertFalse(result.items[2].hasDiagnostic)
    XCTAssertTrue(result.items[3].hasDiagnostic)
  }

  func testSemanticScoreInit() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        enum E {
          case good
          init(_ param: Int, param2: String) { self = .good }
          func test() {
            let _: E = .1️⃣
          }
          func test2() {
            let local = 1
            E(2️⃣)
          }
        }
        """,
      compilerArguments: [path]
    )

    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    guard result1.items.count >= 2 else {
      XCTFail("Expected at least 2 results; received \(result1)")
      return
    }
    XCTAssertEqual(result1.items[0].description, "good")
    XCTAssertEqual(result1.items[1].description, "init(param: Int, param2: String)")
    XCTAssertGreaterThan(result1.items[0].semanticScore, result1.items[1].semanticScore)

    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["2️⃣"],
      filter: ""
    )
    guard result2.items.count >= 2 else {
      XCTFail("Expected at least 2 results; received \(result2)")
      return
    }
    XCTAssertEqual(result2.items[0].description, "(param: Int, param2: String)")
    XCTAssertEqual(result2.items[1].description, "local")
    XCTAssertGreaterThan(result2.items[0].semanticScore, result2.items[1].semanticScore)
  }

  func testSemanticScoreComponents() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct Animal {
          var name = "Test"
          func breed() { }
        }
        let animal = Animal()
        animal.1️⃣
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      flags: [.includeSemanticComponents]
    )

    XCTAssertEqual(result.items.count, 3)
    for item in result.items {
      let data = Data(base64Encoded: try unwrap(item.semanticScoreComponents))!
      let bytes = [UInt8](data)
      XCTAssertFalse(bytes.isEmpty)
      let classification = try SemanticClassification(byteRepresentation: bytes)
      XCTAssertEqual(classification.score, item.semanticScore)
    }
  }

  func testMemberAccessTypes() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath(fileName: "AnimalKit.swift")
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        class Animal { }
        class Dog: Animal {
          var name = "Test"
          func breed() { }
        }
        let dog = Dog()
        dog1️⃣.
        """,
      compilerArguments: [path]
    )

    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    XCTAssertEqual(result1.memberAccessTypes, ["AnimalKit.Dog", "AnimalKit.Animal"])
    guard result1.items.count == 5 else {
      XCTFail("Expected 5 result. Received \(result1)")
      return
    }
    XCTAssertEqual(result1.items[0].module, "AnimalKit")
    XCTAssertEqual(result1.items[0].name, "name")
    XCTAssertEqual(result1.items[1].module, "AnimalKit")
    XCTAssertEqual(result1.items[1].name, "breed()")

    let result2 = try await sourcekitd.completeUpdate(
      path: path,
      position: positions["1️⃣"],
      filter: "name"
    )
    XCTAssertEqual(result2.memberAccessTypes, ["AnimalKit.Dog", "AnimalKit.Animal"])
    guard result2.items.count == 1 else {
      XCTFail("Expected 1 result. Received \(result2)")
      return
    }
    XCTAssertEqual(result2.items[0].module, "AnimalKit")
    XCTAssertEqual(result2.items[0].name, "name")
  }

  func testTypeModule() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath(fileName: "AnimalKit.swift")
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        class Animal { }
        class Dog: Animal {
          var name = "Test"
          func breed() { }
        }
        AnimalKit1️⃣.
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    XCTAssertEqual(result.memberAccessTypes, [])
    XCTAssertEqual(result.items.count, 2)
    // Note: the order of `Animal` and `Dog` isn't stable.
    for item in result.items {
      XCTAssertEqual(item.module, "AnimalKit")
    }
  }

  func testKeyword() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        1️⃣
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "extensio"
    )
    XCTAssertEqual(result.memberAccessTypes, [])
    guard result.items.count == 1 else {
      XCTFail("Expected 1 result. Received \(result)")
      return
    }
    XCTAssertEqual(result.items[0].name, "extension")
    XCTAssertNil(result.items[0].module)
  }

  func testSemanticScoreComponentsAsExtraUpdate() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func test() {
            self.1️⃣
          }
        }
        """,
      compilerArguments: [path]
    )

    // Open without `includeSemanticComponents`.
    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    XCTAssertEqual(result1.items.count, 2)
    for item in result1.items {
      XCTAssertNil(item.semanticScoreComponents)
    }

    // Update without `includeSemanticComponents`.
    let result2 = try await sourcekitd.completeUpdate(
      path: path,
      position: positions["1️⃣"],
      filter: "t"
    )
    XCTAssertEqual(result2.items.count, 1)
    for item in result2.items {
      XCTAssertNil(item.semanticScoreComponents)
    }

    // Now, do the same update _with_ `includeSemanticComponents`.
    let result3 = try await sourcekitd.completeUpdate(
      path: path,
      position: positions["1️⃣"],
      filter: "t",
      flags: [.includeSemanticComponents]
    )
    XCTAssertEqual(result3.items.count, 1)
    for item in result3.items {
      // Assert we get `semanticScoreComponents`,
      // when `update` is called with different options than `open`.
      XCTAssertNotNil(item.semanticScoreComponents)
    }

    // Same update _without_ `includeSemanticComponents`.
    let result4 = try await sourcekitd.completeUpdate(
      path: path,
      position: positions["1️⃣"],
      filter: "t"
    )
    XCTAssertEqual(result4.items.count, 1)
    for item in result4.items {
      // Response no longer contains the `semanticScoreComponents`.
      XCTAssertNil(item.semanticScoreComponents)
    }
  }

  // rdar://104381080 (NSImage(imageLiteralResourceName:) was my top completion — this seems odd)
  func testPopularityForTypeFromSubmodule() async throws {
    #if !os(macOS)
    try XCTSkipIf(true, "AppKit is only defined on macOS")
    #endif
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        import AppKit
        func test() {
          1️⃣
        }
        """,
      compilerArguments: [path]
    )

    let popularityIndex = """
      {
        "AppKit": {
          "scores": [
            0.6
          ],
          "values": [
            "NSImage"
          ]
        }
      }
      """
    try await withTestScratchDir { scratchDir in
      let popularityIndexPath = scratchDir.appending(component: "popularityIndex.json")
      try popularityIndex.write(to: popularityIndexPath, atomically: true, encoding: .utf8)
      try await sourcekitd.setPopularityIndex(
        scopedPopularityDataPath: try popularityIndexPath.filePath,
        popularModules: [],
        notoriousModules: []
      )

      let result = try await sourcekitd.completeOpen(
        path: path,
        position: positions["1️⃣"],
        filter: "",
        flags: [.addInitsToTopLevel]
      )
      // `NSImage` is defined in `AppKit.NSImage` (a submodule).
      // The popularity index is keyed only on the base module (e.g. `AppKit`).
      // This asserts we correctly see `NSImage` as popular.
      XCTAssertEqual(result.items.first?.description, "NSImage")
    }
  }

  func testPopularity() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func test() {
            self.1️⃣
          }
          let popular: Int = 0
          let other1: Int = 0
          let unpopular: Int = 0
          let other2: Int = 0
          let recent1: Int = 0
          let recent2: Int = 0
          let other3: Int = 0
        }
        """,
      compilerArguments: [path]
    )

    // Reset the scoped popularity data path if it was set by previous requests
    try await sourcekitd.setPopularityIndex(
      scopedPopularityDataPath: "/invalid",
      popularModules: [],
      notoriousModules: []
    )

    try await sourcekitd.setPopularAPI(popular: ["popular"], unpopular: ["unpopular"])

    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      recentCompletions: ["recent1"]
    )
    guard result1.items.count >= 6 else {
      XCTFail("Expected at least 6 results. Received \(result1)")
      return
    }
    XCTAssertEqual(result1.items[0].description, "popular")
    XCTAssertEqual(result1.items[1].description, "recent1")
    XCTAssertEqual(result1.items[2].description, "other1")
    XCTAssertEqual(result1.items.last?.description, "unpopular")

    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      recentCompletions: ["recent2", "recent1"]
    )

    guard result2.items.count >= 6 else {
      XCTFail("Expected at least 6 results. Received \(result2)")
      return
    }
    XCTAssertEqual(result2.items[0].description, "popular")
    XCTAssertEqual(result2.items[1].description, "recent2")
    XCTAssertEqual(result2.items[2].description, "recent1")
    XCTAssertEqual(result2.items[3].description, "other1")
    XCTAssertEqual(result2.items.last?.description, "unpopular")

    try await sourcekitd.setPopularAPI(popular: [], unpopular: [])

    let result3 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      recentCompletions: ["recent2", "recent1"]
    )
    guard result3.items.count >= 6 else {
      XCTFail("Expected at least 6 results. Received \(result3)")
      return
    }
    XCTAssertEqual(result3.items[0].description, "recent2")
    XCTAssertEqual(result3.items[1].description, "recent1")
    // Results 2 - 6 share the same score
    XCTAssertEqual(result3.items[2].description, "popular")
    XCTAssertEqual(result3.items[3].description, "other1")
    XCTAssertEqual(result3.items[4].description, "unpopular")
    XCTAssertEqual(result3.items[5].description, "other2")
    XCTAssertEqual(result3.items[6].description, "other3")
    XCTAssertEqual(result3.items[2].semanticScore, result3.items[3].semanticScore)
    XCTAssertEqual(result3.items[2].semanticScore, result3.items[4].semanticScore)
    XCTAssertEqual(result3.items[2].semanticScore, result3.items[5].semanticScore)
    XCTAssertEqual(result3.items[2].semanticScore, result3.items[6].semanticScore)
  }

  func testScopedPopularity() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct Strinz: Encodable {
          var aProp: String = ""
          var value: Int = 12
        }
        func test(arg: Strinz) {
          arg.1️⃣
        }
        func testGlobal() {
          2️⃣
        }
        """,
      compilerArguments: [path, "-module-name", "MyMod"]
    )

    let popularityIndex = """
      {
        "Swift.Encodable": {
          "values": [
            "encode"
          ],
          "scores": [
            1.0
          ]
        }
      }
      """

    try await withTestScratchDir { scratchDir in
      let popularityIndexPath = scratchDir.appending(component: "popularityIndex.json")
      try popularityIndex.write(to: popularityIndexPath, atomically: true, encoding: .utf8)

      let result1 = try await sourcekitd.completeOpen(
        path: path,
        position: positions["1️⃣"],
        filter: ""
      )
      let scoreWithoutPopularity = try XCTUnwrap(result1.items.first(where: { $0.name == "encode(to:)" })).semanticScore

      try await sourcekitd.setPopularityIndex(
        scopedPopularityDataPath: try popularityIndexPath.filePath,
        popularModules: [],
        notoriousModules: ["MyMod"]
      )

      let result2 = try await sourcekitd.completeOpen(
        path: path,
        position: positions["1️⃣"],
        filter: ""
      )
      let scoreWithPopularity = try XCTUnwrap(result2.items.first(where: { $0.name == "encode(to:)" })).semanticScore

      XCTAssert(scoreWithoutPopularity < scoreWithPopularity)

      // Ensure 'notoriousModules' lowers the score.
      let result3 = try await sourcekitd.completeOpen(
        path: path,
        position: positions["2️⃣"],
        filter: "Strin",
        recentCompletions: []
      )
      let string = try XCTUnwrap(result3.items.first(where: { $0.name == "String" }))
      let strinz = try XCTUnwrap(result3.items.first(where: { $0.name == "Strinz" }))
      XCTAssert(string.textMatchScore == strinz.textMatchScore)
      XCTAssert(string.semanticScore > strinz.semanticScore)
    }
  }

  func testModulePopularity() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func test() {
            self.1️⃣
          }
          let foo: Int = 0
        }
        """,
      compilerArguments: [path]
    )

    try await sourcekitd.setPopularityTable(
      PopularityTable(moduleSymbolReferenceTables: [], recentCompletions: [], popularModules: [], notoriousModules: [])
    )

    let result1 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      recentCompletions: []
    )
    let noPopularModulesScore = try unwrap(result1.items.first(where: { $0.description == "foo" })?.semanticScore)

    try await sourcekitd.setPopularityTable(
      PopularityTable(
        moduleSymbolReferenceTables: [],
        recentCompletions: [],
        popularModules: ["a"],
        notoriousModules: []
      )
    )

    let result2 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      recentCompletions: []
    )
    let moduleIsPopularScore = try unwrap(result2.items.first(where: { $0.description == "foo" })?.semanticScore)

    try await sourcekitd.setPopularityTable(
      PopularityTable(
        moduleSymbolReferenceTables: [],
        recentCompletions: [],
        popularModules: [],
        notoriousModules: ["a"]
      )
    )

    let result3 = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: "",
      recentCompletions: []
    )
    let moduleIsUnpopularScore = try unwrap(result3.items.first(where: { $0.description == "foo" })?.semanticScore)

    XCTAssertLessThan(moduleIsUnpopularScore, noPopularModulesScore)
    XCTAssertLessThan(noPopularModulesScore, moduleIsPopularScore)
  }

  func testFlair() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        struct S {
          func foo(x: Int, y: Int) {}
          func foo(_ arg: String) {}
          func test(localArg: String) {
            self.foo(1️⃣)
          }
        }
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(
      path: path,
      position: positions["1️⃣"],
      filter: ""
    )
    guard result.items.count >= 3 else {
      XCTFail("Expected at least 3 results. Received \(result)")
      return
    }
    XCTAssertTrue(Set(result.items[0...1].map(\.description)) == ["(arg: String)", "(x: Int, y: Int)"])
    XCTAssertTrue(result.items[2...].contains(where: { $0.description == "localArg" }))
  }

  func testPluginFilterAndSortPerfAllMatch() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let (position, recent) = try await sourcekitd.perfTestSetup(path: path)

    let initResult = try await sourcekitd.completeOpen(
      path: path,
      position: position,
      filter: "",
      recentCompletions: recent
    )
    XCTAssertEqual(initResult.items.count, 200)

    self.measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
      assertNoThrow {
        self.startMeasuring()
        let result = try runAsync {
          return try await sourcekitd.completeUpdate(
            path: path,
            position: position,
            filter: ""
          )
        }
        self.stopMeasuring()
        XCTAssertEqual(result.items.count, 200)

        try runAsync {
          // Use a non-matching search to ensure we aren't caching the results.
          let resetResult = try await sourcekitd.completeUpdate(
            path: path,
            position: position,
            filter: "sadfasdfasd"
          )
          XCTAssertEqual(resetResult.items.count, 0)
        }
      }
    }
  }

  func testPluginFilterAndSortPerfFiltered() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let (position, recent) = try await sourcekitd.perfTestSetup(path: path)

    let initResult = try await sourcekitd.completeOpen(
      path: path,
      position: position,
      filter: "",
      recentCompletions: recent
    )
    XCTAssertGreaterThanOrEqual(initResult.unfilteredResultCount, initResult.items.count)

    self.measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
      assertNoThrow {
        self.startMeasuring()
        let result = try runAsync {
          try await sourcekitd.completeUpdate(
            path: path,
            position: position,
            filter: "mMethS"
          )
        }
        self.stopMeasuring()
        XCTAssertEqual(result.items.count, 200)

        try runAsync {
          // Use a non-matching search to ensure we aren't caching the results.
          let resetResult = try await sourcekitd.completeUpdate(
            path: path,
            position: position,
            filter: "sadfasdfasd"
          )
          XCTAssertEqual(resetResult.items.count, 0)
        }
      }
    }
  }

  func testCrossModuleCompletion() async throws {
    let project = try await PluginSwiftPMTestProject(files: [
      "Sources/LibA/LibA.swift": """
      public struct LibA {
          public init() {}
          public func method() {}
      }
      """,
      "Sources/LibB/LibB.swift": """
      import LibA
      func test(lib: LibA) {
          lib.1️⃣method()
      }
      """,
      "Package.swift": """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLibrary",
        targets: [
          .target(name: "LibA"),
          .target(name: "LibB", dependencies: ["LibA"]),
        ]
      )
      """,
    ])

    // Open document in sourcekitd
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let libBPath = try project.uri(for: "LibB.swift").pseudoPath
    try await sourcekitd.openDocument(
      libBPath,
      contents: project.contents(of: "LibB.swift"),
      compilerArguments: project.compilerArguments(for: "LibB.swift")
    )

    // Invoke first code completion
    let result = try await sourcekitd.completeOpen(
      path: libBPath,
      position: project.position(of: "1️⃣", in: "LibB.swift"),
      filter: "met"
    )
    XCTAssertEqual(1, result.items.count)
    XCTAssertEqual(result.items.first?.name, "method()")

    // Modify LibA.swift to contain another memeber on the `LibA` struct
    let modifiedLibA = """
      \(try project.contents(of: "LibA.swift"))
      extension LibA {
        public var meta: Int { 0 }
      }
      """
    try modifiedLibA.write(to: project.uri(for: "LibA.swift").fileURL!, atomically: true, encoding: .utf8)
    try await SwiftPMTestProject.build(at: project.scratchDirectory)

    // Tell sourcekitd that dependencies have been updated and run completion again.
    try await sourcekitd.dependencyUpdated()
    let result2 = try await sourcekitd.completeOpen(
      path: libBPath,
      position: project.position(of: "1️⃣", in: "LibB.swift"),
      filter: "met"
    )
    XCTAssertEqual(Set(result2.items.map(\.name)), ["meta", "method()"])
  }

  func testCompletionImportDepth() async throws {
    let project = try await PluginSwiftPMTestProject(files: [
      "Sources/Main/Main.swift": """
      import Depth1Module

      struct Depth0Struct {}

      func test() {
          1️⃣
          return
      }
      """,
      "Sources/Depth1Module/Depth1.swift": """
      @_exported import Depth2Module
      public struct Depth1Struct {}
      """,
      "Sources/Depth2Module/Depth2.swift": """
      public struct Depth2Struct {}
      """,
      "Package.swift": """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLibrary",
        targets: [
          .executableTarget(name: "Main", dependencies: ["Depth1Module"]),
          .target(name: "Depth1Module", dependencies: ["Depth2Module"]),
          .target(name: "Depth2Module"),
        ]
      )
      """,
    ])

    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let mainPath = try project.uri(for: "Main.swift").pseudoPath
    try await sourcekitd.openDocument(
      mainPath,
      contents: project.contents(of: "Main.swift"),
      compilerArguments: project.compilerArguments(for: "Main.swift")
    )

    let result = try await sourcekitd.completeOpen(
      path: mainPath,
      position: project.position(of: "1️⃣", in: "Main.swift"),
      filter: "depth"
    )

    let depth0struct = try unwrap(result.items.first(where: { $0.name == "Depth0Struct" }))
    let depth1struct = try unwrap(result.items.first(where: { $0.name == "Depth1Struct" }))
    let depth2struct = try unwrap(result.items.first(where: { $0.name == "Depth2Struct" }))
    let depth1module = try unwrap(result.items.first(where: { $0.name == "Depth1Module" }))
    let depth2module = try unwrap(result.items.first(where: { $0.name == "Depth2Module" }))

    XCTAssertGreaterThan(depth0struct.semanticScore, depth1struct.semanticScore)
    XCTAssertGreaterThan(depth1struct.semanticScore, depth2struct.semanticScore)

    // Since "module" entry doesn't have "import depth", we only checks that modules are de-prioritized.
    XCTAssertGreaterThan(depth2struct.semanticScore, depth1module.semanticScore)
    XCTAssertGreaterThan(depth2struct.semanticScore, depth2module.semanticScore)
  }

  func testCompletionDiagnostics() async throws {
    #if !os(macOS)
    try XCTSkipIf(true, "Soft deprecation is only defined for macOS in this test case")
    #endif
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        import 1️⃣Swift
        struct S: P {
          @available(*, deprecated)
          func deprecatedF() {}
          func test() {
            self.2️⃣
          }
          var theVariable: Int {
        3️⃣
          }
          @available(macOS, deprecated: 100000.0)
          func softDeprecatedF() {}
        }
        """,
      compilerArguments: [path]
    )

    let result1 = try await sourcekitd.completeOpen(path: path, position: positions["1️⃣"], filter: "Swift")
    let swiftResult = try unwrap(result1.items.filter({ $0.description == "Swift" }).first)
    XCTAssertEqual(swiftResult.description, "Swift")
    XCTAssertEqual(swiftResult.hasDiagnostic, true)

    let diag1 = try unwrap(try await sourcekitd.completeDiagnostic(id: swiftResult.id))

    XCTAssertEqual(diag1.severity, sourcekitd.values.diagWarning)
    XCTAssertEqual(diag1.description, "module 'Swift' is already imported")

    let result2 = try await sourcekitd.completeOpen(path: path, position: positions["2️⃣"], filter: "deprecatedF")
    guard result2.items.count >= 2 else {
      XCTFail("Expected at least 2 results. Received \(result2)")
      return
    }

    XCTAssertEqual(result2.items[0].description, "deprecatedF()")
    XCTAssertEqual(result2.items[0].hasDiagnostic, true)
    let diag2_0 = try unwrap(try await sourcekitd.completeDiagnostic(id: result2.items[0].id))
    XCTAssertEqual(diag2_0.severity, sourcekitd.values.diagWarning)
    XCTAssertEqual(diag2_0.description, "'deprecatedF()' is deprecated")

    XCTAssertEqual(result2.items[1].description, "softDeprecatedF()")
    XCTAssertEqual(result2.items[1].hasDiagnostic, true)
    let diag2_1 = try unwrap(try await sourcekitd.completeDiagnostic(id: result2.items[1].id))
    XCTAssertEqual(diag2_1.severity, sourcekitd.values.diagWarning)
    XCTAssertEqual(diag2_1.description, "'softDeprecatedF()' will be deprecated in a future version of macOS")

    let result4 = try await sourcekitd.completeOpen(path: path, position: positions["3️⃣"], filter: "theVariable")
    guard result4.items.count >= 1 else {
      XCTFail("Expected at least 1 results. Received \(result4)")
      return
    }
    XCTAssertEqual(result4.items[0].description, "theVariable")
    XCTAssertEqual(result4.items[0].hasDiagnostic, true)

    let diag4_0 = try unwrap(try await sourcekitd.completeDiagnostic(id: result4.items[0].id))

    XCTAssertEqual(diag4_0.severity, sourcekitd.values.diagWarning)
    XCTAssertEqual(diag4_0.description, "attempting to access 'theVariable' within its own getter")
  }

  func testActorKind() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        actor MyActor {
        }
        func test() {
        1️⃣}
        """,
      compilerArguments: [path]
    )

    let result = try await sourcekitd.completeOpen(path: path, position: positions["1️⃣"], filter: "My")
    let actorItem = try unwrap(result.items.first { item in item.description == "MyActor" })
    XCTAssertEqual(actorItem.kind, sourcekitd.values.declActor)
  }

  func testMacroKind() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    let positions = try await sourcekitd.openDocument(
      path,
      contents: """
        @attached(conformance) public macro MyConformance() =  #externalMacro(module: "MyMacros", type: "MyConformanceMacro")
        @freestanding(expression) public macro MyExpression(_: Any) -> String = #externalMacro(module: "MyMacros", type: "MyExpressionMacro")

        func testAttached() {
        @1️⃣
        }
        func testFreestanding() {
        _ = #2️⃣
        }
        """,
      compilerArguments: [path]
    )

    let result1 = try await sourcekitd.completeOpen(path: path, position: positions["1️⃣"], filter: "My")
    let macroItem1 = try unwrap(result1.items.first { item in item.name == "MyConformance" })
    XCTAssertEqual(macroItem1.kind, sourcekitd.values.declMacro)

    let result2 = try await sourcekitd.completeOpen(path: path, position: positions["2️⃣"], filter: "My")
    let macroItem2 = try unwrap(result2.items.first { item in item.name.starts(with: "MyExpression") })
    XCTAssertEqual(macroItem2.kind, sourcekitd.values.declMacro)

  }

  func testMaxResults() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()
    let sourcekitd = try await getSourceKitD()
    let path = scratchFilePath()
    var sourceText = "//dummy\n";
    for i in 0..<200 {
      /// Create at least 200 (default maxResults) items
      sourceText += """
        func foo\(i)() {}

        """
    }
    try await sourcekitd.openDocument(path, contents: sourceText, compilerArguments: [path])

    let position = Position(line: 200, utf16index: 0)

    let result1 = try await sourcekitd.completeOpen(path: path, position: position, filter: "f", maxResults: 3)
    XCTAssertEqual(result1.items.count, 3)

    let result2 = try await sourcekitd.completeUpdate(path: path, position: position, filter: "fo", maxResults: 5)
    XCTAssertEqual(result2.items.count, 5)

    let result3 = try await sourcekitd.completeUpdate(path: path, position: position, filter: "f")
    XCTAssertEqual(result3.items.count, 200)
  }
}

// MARK: - Structured result types

private struct CompletionResultSet: Sendable {
  var unfilteredResultCount: Int
  var memberAccessTypes: [String]
  var items: [CompletionResult]

  init(_ dict: SKDResponseDictionary) throws {
    let keys = dict.sourcekitd.keys
    guard let unfilteredResultCount: Int = dict[keys.unfilteredResultCount],

      let memberAccessTypes = dict[keys.memberAccessTypes]?.asStringArray,
      let results: SKDResponseArray = dict[keys.results]
    else {
      throw TestError(
        "expected {key.results: <array>, key.unfiltered_result_count: <int64>}; got \(dict)"
      )
    }

    self.unfilteredResultCount = unfilteredResultCount
    self.memberAccessTypes = memberAccessTypes
    self.items =
      try results
      .map { try CompletionResult($0) }
      .sorted(by: { $0.semanticScore > $1.semanticScore })

    XCTAssertGreaterThanOrEqual(
      self.unfilteredResultCount,
      self.items.count,
      "unfiltered_result_count must be greater than or equal to the count of results"
    )
  }
}

private struct CompletionResult: Equatable, Sendable {
  nonisolated(unsafe) var kind: sourcekitd_api_uid_t
  var id: Int
  var name: String
  var description: String
  var sourcetext: String
  var module: String?
  var typename: String
  var textMatchScore: Double
  var semanticScore: Double
  var semanticScoreComponents: String?
  var priorityBucket: Int
  var isSystem: Bool
  var numBytesToErase: Int
  var hasDiagnostic: Bool
  var groupID: Int?

  init(_ dict: SKDResponseDictionary) throws {
    let keys = dict.sourcekitd.keys

    guard let kind: sourcekitd_api_uid_t = dict[keys.kind],
      let id: Int = dict[keys.identifier],
      let name: String = dict[keys.name],
      let description: String = dict[keys.description],
      let sourcetext: String = dict[keys.sourceText],
      let typename: String = dict[keys.typeName],
      let textMatchScore: Double = dict[keys.textMatchScore],
      let semanticScore: Double = dict[keys.semanticScore],
      let priorityBucket: Int = dict[keys.priorityBucket],
      let isSystem: Bool = dict[keys.isSystem],
      let hasDiagnostic: Bool = dict[keys.hasDiagnostic]
    else {
      throw TestError("Failed to decode CompletionResult. Received \(dict)")
    }

    self.kind = kind
    self.id = id
    self.name = name
    self.description = description
    self.sourcetext = sourcetext
    self.module = dict[keys.moduleName]
    self.typename = typename
    self.textMatchScore = textMatchScore
    self.semanticScore = semanticScore
    self.semanticScoreComponents = dict[keys.semanticScoreComponents]
    self.priorityBucket = priorityBucket
    self.isSystem = isSystem
    self.numBytesToErase = dict[keys.numBytesToErase] ?? 0
    self.hasDiagnostic = hasDiagnostic
    self.groupID = dict[keys.groupId]
    assert(self.groupID != 0)
  }
}

private struct CompletionDocumentation {
  var docComment: String? = nil
  var docFullAsXML: String? = nil
  var docBrief: String? = nil
  var associatedUSRs: [String] = []

  init(_ dict: SKDResponseDictionary) {
    let keys = dict.sourcekitd.keys
    self.docComment = dict[keys.docComment]
    self.docFullAsXML = dict[keys.docFullAsXML]
    self.docBrief = dict[keys.docBrief]
    self.associatedUSRs = dict[keys.associatedUSRs]?.asStringArray ?? []
  }
}

private struct CompletionDiagnostic {
  var severity: sourcekitd_api_uid_t
  var description: String

  init?(_ dict: SKDResponseDictionary) {
    let keys = dict.sourcekitd.keys
    guard
      let severity: sourcekitd_api_uid_t = dict[keys.severity],
      let description: String = dict[keys.description]
    else {
      return nil
    }
    self.severity = severity
    self.description = description
  }
}

private struct TestError: Error {
  let error: String

  init(_ message: String) {
    self.error = message
  }
}

// MARK: - sourcekitd convenience functions

struct CompletionRequestFlags: OptionSet {
  let rawValue: Int
  static let annotate: Self = .init(rawValue: 1 << 0)
  static let addInitsToTopLevel: Self = .init(rawValue: 1 << 1)
  static let addCallWithNoDefaultArgs: Self = .init(rawValue: 1 << 2)
  static let includeSemanticComponents: Self = .init(rawValue: 1 << 3)
}

fileprivate extension SourceKitD {
  @discardableResult
  nonisolated func openDocument(
    _ name: String,
    contents markedSource: String,
    compilerArguments: [String]? = nil
  ) async throws -> DocumentPositions {
    let (markers, textWithoutMarkers) = extractMarkers(markedSource)
    var compilerArguments = compilerArguments ?? [name]
    if let defaultSDKPath {
      compilerArguments += ["-sdk", defaultSDKPath]
    }
    let req = dictionary([
      keys.name: name,
      keys.sourceText: textWithoutMarkers,
      keys.syntacticOnly: 1,
      keys.compilerArgs: compilerArguments as [any SKDRequestValue],
    ])
    _ = try await send(\.editorOpen, req)
    return DocumentPositions(markers: markers, textWithoutMarkers: textWithoutMarkers)
  }

  nonisolated func editDocument(_ name: String, fromOffset offset: Int, length: Int, newContents: String) async throws {
    let req = dictionary([
      keys.name: name,
      keys.offset: offset,
      keys.length: length,
      keys.sourceText: newContents,
      keys.syntacticOnly: 1,
    ])

    _ = try await send(\.editorReplaceText, req)
  }

  nonisolated func closeDocument(_ name: String) async throws {
    let req = dictionary([
      keys.name: name
    ])

    _ = try await send(\.editorClose, req)
  }

  nonisolated func completeImpl(
    requestUID: any KeyPath<sourcekitd_api_requests, sourcekitd_api_uid_t> & Sendable,
    path: String,
    position: Position,
    filter: String,
    recentCompletions: [String]? = nil,
    flags: CompletionRequestFlags = [],
    useXPC: Bool = false,
    maxResults: Int? = nil,
    compilerArguments: [String]? = nil
  ) async throws -> CompletionResultSet {
    let options = dictionary([
      keys.useNewAPI: 1,
      keys.annotatedDescription: flags.contains(.annotate) ? 1 : 0,
      keys.addInitsToTopLevel: flags.contains(.addInitsToTopLevel) ? 1 : 0,
      keys.addCallWithNoDefaultArgs: flags.contains(.addCallWithNoDefaultArgs) ? 1 : 0,
      keys.includeSemanticComponents: flags.contains(.includeSemanticComponents) ? 1 : 0,
      keys.filterText: filter,
      keys.recentCompletions: recentCompletions as [any SKDRequestValue]?,
      keys.maxResults: maxResults,
    ])

    let req = dictionary([
      keys.line: position.line + 1,
      // Technically sourcekitd needs a UTF-8 index but we can assume there are no Unicode characters in the tests
      keys.column: position.utf16index + 1,
      keys.sourceFile: path,
      keys.codeCompleteOptions: options,
      keys.compilerArgs: compilerArguments as [any SKDRequestValue]?,
    ])

    let res = try await send(requestUID, req)
    return try CompletionResultSet(res)
  }

  nonisolated func completeOpen(
    path: String,
    position: Position,
    filter: String,
    recentCompletions: [String]? = nil,
    flags: CompletionRequestFlags = [],
    useXPC: Bool = false,
    maxResults: Int? = nil,
    compilerArguments: [String]? = nil
  ) async throws -> CompletionResultSet {
    return try await completeImpl(
      requestUID: \.codeCompleteOpen,
      path: path,
      position: position,
      filter: filter,
      recentCompletions: recentCompletions,
      flags: flags,
      useXPC: useXPC,
      maxResults: maxResults,
      compilerArguments: compilerArguments
    )
  }

  nonisolated func completeUpdate(
    path: String,
    position: Position,
    filter: String,
    flags: CompletionRequestFlags = [],
    useXPC: Bool = false,
    maxResults: Int? = nil
  ) async throws -> CompletionResultSet {
    return try await completeImpl(
      requestUID: \.codeCompleteUpdate,
      path: path,
      position: position,
      filter: filter,
      recentCompletions: nil,
      flags: flags,
      useXPC: useXPC,
      maxResults: maxResults,
      compilerArguments: nil
    )
  }

  nonisolated func completeClose(path: String, position: Position) async throws {
    let req = dictionary([
      keys.line: position.line + 1,
      // Technically sourcekitd needs a UTF-8 index but we can assume there are no Unicode characters in the tests
      keys.column: position.utf16index + 1,
      keys.sourceFile: path,
      keys.codeCompleteOptions: dictionary([keys.useNewAPI: 1]),
    ])

    _ = try await send(\.codeCompleteClose, req)
  }

  nonisolated func completeDocumentation(id: Int) async throws -> CompletionDocumentation {
    let resp = try await send(\.codeCompleteDocumentation, dictionary([keys.identifier: id]))
    return CompletionDocumentation(resp)
  }

  nonisolated func completeDiagnostic(id: Int) async throws -> CompletionDiagnostic? {
    let resp = try await send(\.codeCompleteDiagnostic, dictionary([keys.identifier: id]))

    return CompletionDiagnostic(resp)
  }

  nonisolated func dependencyUpdated() async throws {
    _ = try await send(\.dependencyUpdated, dictionary([:]))
  }

  nonisolated func setPopularAPI(popular: [String], unpopular: [String]) async throws {
    let req = dictionary([
      keys.codeCompleteOptions: dictionary([keys.useNewAPI: 1]),
      keys.popular: popular as [any SKDRequestValue],
      keys.unpopular: unpopular as [any SKDRequestValue],
    ])

    let resp = try await send(\.codeCompleteSetPopularAPI, req)
    XCTAssertEqual(resp[keys.useNewAPI], 1)
  }

  nonisolated func setPopularityIndex(
    scopedPopularityDataPath: String,
    popularModules: [String],
    notoriousModules: [String]
  ) async throws {
    let req = dictionary([
      keys.codeCompleteOptions: dictionary([keys.useNewAPI: 1]),
      keys.scopedPopularityTablePath: scopedPopularityDataPath,
      keys.popularModules: popularModules as [any SKDRequestValue],
      keys.notoriousModules: notoriousModules as [any SKDRequestValue],
    ])

    let resp = try await send(\.codeCompleteSetPopularAPI, req)
    XCTAssertEqual(resp[keys.useNewAPI], 1)
  }

  func setPopularityTable(_ popularityTable: PopularityTable) async throws {
    let symbolPopularity = popularityTable.symbolPopularity.map { key, value in
      dictionary([
        keys.popularityKey: key,
        keys.popularityValueIntBillion: Int(value.scoreComponent * 1_000_000_000),
      ])
    }
    let modulePopularity = popularityTable.modulePopularity.map { key, value in
      dictionary([
        keys.popularityKey: key,
        keys.popularityValueIntBillion: Int(value.scoreComponent * 1_000_000_000),
      ])
    }
    let req = dictionary([
      keys.codeCompleteOptions: dictionary([keys.useNewAPI: 1]),
      keys.symbolPopularity: symbolPopularity as [any SKDRequestValue],
      keys.modulePopularity: modulePopularity as [any SKDRequestValue],
    ])

    let resp = try await send(\.codeCompleteSetPopularAPI, req)
    XCTAssertEqual(resp[keys.useNewAPI], 1)
  }

  func perfTestSetup(path: String) async throws -> (Position, recent: [String]) {
    var content = """
      struct S {
        func test() {
          self.1️⃣
        }
      """

    #if DEBUG
    let numMethods = 1_000
    #else
    let numMethods = 100_000
    #endif

    var popular: [String] = []
    var unpopular: [String] = []

    for i in 0..<numMethods {
      content += "\n  func myMethodWithSomeWords\(i)() {}"
      if i % 200 == 0 {
        popular.append("myMethodWithSomeWords\(i)()")
      }
      if i % 200 == 3 {
        unpopular.append("myMethodWithSomeWords\(i)()")
      }
    }
    content += "\n}"

    var recent: [String] = []
    for _ in 0..<100 {
      recent.append("myMethodWithSomeWords\((0..<numMethods).randomElement()!)()")
    }

    let (markers, textWithoutMarker) = extractMarkers(content)
    let positions = DocumentPositions(markers: markers, textWithoutMarkers: textWithoutMarker)

    try await setPopularAPI(popular: popular, unpopular: unpopular)
    try await openDocument(path, contents: textWithoutMarker, compilerArguments: [path])
    return (positions["1️⃣"], recent)
  }
}

private struct ExpectationNotFulfilledError: Error {}

/// Run the given async block and block the current function until `body` terminates.
private func runAsync<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
  nonisolated(unsafe) var result: Result<T, any Error>!
  let expectation = XCTestExpectation(description: "")
  Task {
    do {
      result = .success(try await body())
    } catch {
      result = .failure(error)
    }
    expectation.fulfill()
  }
  let started = XCTWaiter.wait(for: [expectation], timeout: defaultTimeout)
  if started != .completed {
    throw ExpectationNotFulfilledError()
  }
  return try result.get()
}
