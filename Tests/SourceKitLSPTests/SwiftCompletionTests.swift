//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import XCTest

final class SwiftCompletionTests: XCTestCase {
  // MARK: - Helpers

  private var snippetCapabilities = ClientCapabilities(
    textDocument: TextDocumentClientCapabilities(
      completion: TextDocumentClientCapabilities.Completion(
        completionItem: TextDocumentClientCapabilities.Completion.CompletionItem(snippetSupport: true)
      )
    )
  )

  // MARK: - Tests

  func testCompletionBasic() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct S {
        /// Documentation for `abc`.
        var abc: Int

        func test(a: Int) {
          self.1️⃣abc
      2️⃣  }

        func test(_ b: Int) {
          self.abc
        }
      }
      """,
      uri: uri
    )

    let selfDot = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    XCTAssertTrue(selfDot.isIncomplete)
    XCTAssertGreaterThanOrEqual(selfDot.items.count, 2)
    let abc = selfDot.items.first { $0.label == "abc" }
    XCTAssertNotNil(abc)
    if let abc = abc {
      XCTAssertEqual(abc.kind, .property)
      XCTAssertEqual(abc.detail, "Int")
      XCTAssertEqual(abc.documentation, .markupContent(MarkupContent(kind: .markdown, value: "Documentation for abc.")))
      XCTAssertEqual(abc.filterText, "abc")
      XCTAssertEqual(abc.textEdit, .textEdit(TextEdit(range: Range(positions["1️⃣"]), newText: "abc")))
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .plain)
    }

    for columnOffset in 1...3 {
      let offsetPosition = positions["1️⃣"].adding(columns: columnOffset)
      let inIdent = try await testClient.send(
        CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: offsetPosition)
      )
      guard let abc = inIdent.items.first(where: { $0.label == "abc" }) else {
        XCTFail("No completion item with label 'abc'")
        return
      }

      // If we switch to server-side filtering this will change.
      XCTAssertEqual(abc.kind, .property)
      XCTAssertEqual(abc.detail, "Int")
      XCTAssertEqual(abc.documentation, .markupContent(MarkupContent(kind: .markdown, value: "Documentation for abc.")))
      XCTAssertEqual(abc.filterText, "abc")
      XCTAssertEqual(abc.textEdit, .textEdit(TextEdit(range: positions["1️⃣"]..<offsetPosition, newText: "abc")))
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .plain)
    }

    let after = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    XCTAssertNotEqual(after, selfDot)
  }

  func testCompletionSnippetSupport() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct S {
        /// Documentation for `abc`.
        var abc: Int

        func test(a: Int) {
          self.1️⃣abc
        }

        func test(_ b: Int) {
          self.2️⃣abc
        }
      }
      """,
      uri: uri
    )

    func getTestMethodCompletion(_ position: Position, label: String) async throws -> CompletionItem? {
      let selfDot = try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: position
        )
      )
      return selfDot.items.first { $0.label == label }
    }

    var test = try await getTestMethodCompletion(positions["1️⃣"], label: "test(a: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
      XCTAssertEqual(test.textEdit, .textEdit(TextEdit(range: Range(positions["1️⃣"]), newText: "test(a: ${1:Int})")))
      XCTAssertEqual(test.insertText, "test(a: ${1:Int})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }

    test = try await getTestMethodCompletion(positions["2️⃣"], label: "test(b: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(:)")
      XCTAssertEqual(test.textEdit, .textEdit(TextEdit(range: Range(positions["2️⃣"]), newText: "test(${1:Int})")))
      XCTAssertEqual(test.insertText, "test(${1:Int})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }
  }

  func testCompletionNoSnippetSupport() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct S {
        /// Documentation for `abc`.
        var abc: Int

        func test(a: Int) {
          self.1️⃣abc
        }

        func test(_ b: Int) {
          self.2️⃣abc
        }
      }
      """,
      uri: uri
    )

    func getTestMethodCompletion(_ position: Position, label: String) async throws -> CompletionItem? {
      let selfDot = try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: position
        )
      )
      return selfDot.items.first { $0.label == label }
    }

    var test = try await getTestMethodCompletion(positions["1️⃣"], label: "test(a: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
      XCTAssertEqual(test.textEdit, .textEdit(TextEdit(range: Range(positions["1️⃣"]), newText: "test(a: )")))
      XCTAssertEqual(test.insertText, "test(a: )")
      XCTAssertEqual(test.insertTextFormat, .plain)
    }

    test = try await getTestMethodCompletion(positions["2️⃣"], label: "test(b: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(:)")
      XCTAssertEqual(test.textEdit, .textEdit(TextEdit(range: Range(positions["2️⃣"]), newText: "test()")))
      XCTAssertEqual(test.insertText, "test()")
      XCTAssertEqual(test.insertTextFormat, .plain)
    }
  }

  func testCompletionPositionServerFilter() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    testClient.openDocument("foo", uri: uri)

    for col in 0...3 {
      let inOrAfterFoo = try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 0, utf16index: col)
        )
      )
      XCTAssertTrue(inOrAfterFoo.isIncomplete)
      XCTAssertFalse(inOrAfterFoo.items.isEmpty)
    }

    let outOfRange1 = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 0, utf16index: 4)
      )
    )
    XCTAssertTrue(outOfRange1.isIncomplete)

    let outOfRange2 = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 1, utf16index: 0)
      )
    )
    XCTAssertTrue(outOfRange2.isIncomplete)
  }

  func testCompletionOptional() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct Foo {
        let bar: Int
      }
      let a: Foo? = Foo(bar: 1)
      a1️⃣.2️⃣ba
      """,
      uri: uri
    )

    for columnOffset in 0...2 {
      let offsetPosition = positions["2️⃣"].adding(columns: columnOffset)
      let response = try await testClient.send(
        CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: offsetPosition)
      )

      guard let item = response.items.first(where: { $0.label.contains("bar") }) else {
        XCTFail("No completion item with label 'bar'")
        return
      }
      XCTAssertEqual(item.filterText, ".bar")
      XCTAssertEqual(
        item.textEdit,
        .textEdit(
          TextEdit(range: positions["1️⃣"]..<offsetPosition, newText: "?.bar")
        )
      )
    }
  }

  func testCompletionOverride() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      class Base {
        func foo() {}
      }
      class C: Base {
        1️⃣func 2️⃣   // don't delete trailing space in this file
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    guard let item = response.items.first(where: { $0.label == "foo()" }) else {
      XCTFail("No completion item with label 'foo()'")
      return
    }
    // TODO: The filter text should be "foo()" (https://github.com/swiftlang/sourcekit-lsp/issues/1599)
    XCTAssertEqual(item.filterText, "func foo()")
    XCTAssertEqual(
      item.textEdit,
      .textEdit(TextEdit(range: positions["1️⃣"]..<positions["2️⃣"], newText: "override func foo() {\n\n}"))
    )
  }

  func testCompletionOverrideInNewLine() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      class Base {
        func foo() {}
      }
      class C: Base {
        func
        1️⃣  // don't delete trailing space in this file
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )
    guard let item = response.items.first(where: { $0.label == "foo()" }) else {
      XCTFail("No completion item with label 'foo()'")
      return
    }
    // If the edit would cross multiple lines, we are currently not replacing any text. It's not technically correct but the best we can do.
    XCTAssertEqual(item.filterText, "foo()")
    XCTAssertEqual(
      item.textEdit,
      .textEdit(TextEdit(range: Range(positions["1️⃣"]), newText: "override func foo() {\n\n}"))
    )
  }

  func testRefilterAfterIncompleteResults() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct S {
        func fooAbc() {}
        func fooBcd() {}
        func fooCde() {}
        func fooDef() {}
        func fooGoop() {}
        func test() {
      1️⃣    self.f2️⃣cdez
        }
      }
      """,
      uri: uri
    )

    assertEqual(
      5,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["2️⃣"],
            context: CompletionContext(triggerKind: .invoked)
          )
        )
      )
    )

    assertEqual(
      3,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["2️⃣"].adding(columns: 1),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )
    assertEqual(
      2,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["2️⃣"].adding(columns: 2),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )
    assertEqual(
      1,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["2️⃣"].adding(columns: 3),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )
    assertEqual(
      0,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["2️⃣"].adding(columns: 4),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )
    assertEqual(
      2,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["2️⃣"].adding(columns: 2),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    assertEqual(
      1,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["2️⃣"].adding(columns: 3),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    // Trigger kind changed => OK (200 is maxResults since we're outside the member completion)
    assertEqual(
      200,
      try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: positions["1️⃣"],
          context: CompletionContext(triggerKind: .invoked)
        )
      ).items.count
    )
  }

  func testRefilterAfterIncompleteResultsWithEdits() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct S {
        func fooAbc() {}
        func fooBcd() {}
        func fooCde() {}
        func fooDef() {}
        func fooGoop() {}
        func test() {
          self.f1️⃣z
        }
      }
      """,
      uri: uri
    )

    // 'f'
    assertEqual(
      5,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["1️⃣"],
            context: CompletionContext(triggerKind: .invoked)
          )
        )
      )
    )

    // 'fz'
    assertEqual(
      0,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["1️⃣"].adding(columns: 1),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: positions["1️⃣"]..<(positions["1️⃣"].adding(columns: 1)), text: "A ")
        ]
      )
    )

    // 'fA'
    assertEqual(
      1,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["1️⃣"].adding(columns: 1),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    // 'fA '
    assertEqual(
      try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: positions["1️⃣"].adding(columns: 2),
          context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
        )
      ).items,
      []
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: positions["1️⃣"]..<(positions["1️⃣"].adding(columns: 1)), text: "Ab")
        ]
      )
    )

    // 'fAb'
    assertEqual(
      1,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["1️⃣"].adding(columns: 1),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: positions["1️⃣"]..<(positions["1️⃣"].adding(columns: 1)), text: "")
        ]
      )
    )

    // 'fb'
    assertEqual(
      2,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["1️⃣"].adding(columns: 1),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: Range(positions["1️⃣"].adding(columns: 1)), text: "d")
        ]
      )
    )

    // 'fbd'
    assertEqual(
      1,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: positions["1️⃣"].adding(columns: 2),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )
  }

  /// Regression test for https://bugs.swift.org/browse/SR-13561 to make sure the a session
  /// close waits for its respective open to finish to prevent a session geting stuck open.
  func testSessionCloseWaitsforOpen() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct S {
        func forSomethingCrazy() {}
        func forSomethingCool() {}
        func test() {
          self.forS1️⃣ome
        }
        func print() {}
        func anotherOne() {
          self.prin2️⃣
        }
      }
      """,
      uri: uri
    )

    let forSomeComplete = CompletionRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: positions["1️⃣"],
      context: CompletionContext(triggerKind: .invoked)
    )
    let printComplete = CompletionRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: positions["2️⃣"],
      context: CompletionContext(triggerKind: .invoked)
    )

    // Code completion for "self.forSome"
    async let forSomeResult = testClient.send(forSomeComplete)

    // Code completion for "self.prin", previously could immediately invalidate
    // the previous request.
    async let printResult = testClient.send(printComplete)

    assertEqual(2, countFs(try await forSomeResult))
    assertEqual(1, try await printResult.items.count)

    // Try code completion for "self.forSome" again to verify that it still works.
    let result = try await testClient.send(forSomeComplete)
    XCTAssertEqual(2, countFs(result))
  }

  func testCodeCompleteSwiftPackage() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await SwiftPMTestProject(
      files: [
        "a.swift": """
        struct A {
          func method(a b: Int) {}
        }
        """,
        "b.swift": """
        func test(a: A) {
          a.1️⃣
        }
        """,
      ]
    )
    let (uri, positions) = try project.openDocument("b.swift")

    let testPosition = positions["1️⃣"]
    let results = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: testPosition)
    )

    XCTAssertEqual(
      results.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "method(a: Int)",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "method(a:)",
          insertText: "method(a: )",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(
              range: Range(testPosition),
              newText: "method(a: )"
            )
          )
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "A",
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(testPosition), newText: "self")
          )
        ),
      ]
    )
  }

  func testTriggerFromIncompleteAfterStartingStringLiteral() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func foo(_ x: String) {}

      func test() {
        foo1️⃣
      }
      """,
      uri: uri
    )

    // The following is a pattern that VS Code sends. Make sure we don't return an error.
    // - Insert `()``, changing the line to `foo()``
    // - Invoke code completion after `(`
    // - Insert `""`, changing the line to `foo("")`
    // - Insert `d` inside the string literal, changing the line to `foo("d")`
    // - Ask for completion with the `triggerFromIncompleteCompletions` flag set.
    // Since this isn't actually re-filtering but is a completely new code completion session. When we detect this, we
    // should just start a new session and return the results.
    var position = positions["1️⃣"]
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: position.utf16index),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(position), text: "()")]
      )
    )
    position.utf16index += 1
    let initialCompletionResults = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: position)
    )
    // Test that we get the "abc" result which makes VS Code think that we are still in the same completion session when doing hte second completion.
    XCTAssert(initialCompletionResults.items.contains(where: { $0.label == #""abc""# }))
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: position.utf16index),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(position), text: "\"\"")]
      )
    )
    position.utf16index += 1
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: position.utf16index),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(position), text: "d")]
      )
    )
    let secondCompletionResults = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: position,
        context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
      )
    )
    // We shouldn't be getting code completion results for inside the string literal.
    XCTAssert(secondCompletionResults.items.isEmpty)
  }

  func testNonAsciiCompletionFilter() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct Foo {
        func 👨‍👩‍👦👨‍👩‍👦() {}
        func test() {
          self.1️⃣👨‍👩‍👦2️⃣
        }
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    XCTAssertEqual(
      completions.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "👨‍👩‍👦👨‍👩‍👦()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "👨‍👩‍👦👨‍👩‍👦()",
          insertText: "👨‍👩‍👦👨‍👩‍👦()",
          insertTextFormat: .plain,
          textEdit: .textEdit(TextEdit(range: positions["1️⃣"]..<positions["2️⃣"], newText: "👨‍👩‍👦👨‍👩‍👦()"))
        )
      ]
    )
  }

  func testExpandClosurePlaceholder() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct MyArray {
          func myMap(_ body: (Int) -> Bool) {}
      }
      func test(x: MyArray) {
          x.1️⃣
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(
      completions.items.clearingUnstableValues.filter { $0.label.contains("myMap") },
      [
        CompletionItem(
          label: "myMap(body: (Int) -> Bool)",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "myMap(:)",
          insertText: #"""
            myMap(${1:{ ${2:Int} in ${3:Bool} \}})
            """#,
          insertTextFormat: .snippet,
          textEdit: .textEdit(
            TextEdit(
              range: Range(positions["1️⃣"]),
              newText: #"""
                myMap(${1:{ ${2:Int} in ${3:Bool} \}})
                """#
            )
          )
        )
      ]
    )
  }

  func testExpandClosurePlaceholderOnOptional() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct MyArray {
          func myMap(_ body: (Int) -> Bool) {}
      }
      func test(x: MyArray?) {
          x1️⃣.2️⃣
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    XCTAssertEqual(
      completions.items.clearingUnstableValues.filter { $0.label.contains("myMap") },
      [
        CompletionItem(
          label: "myMap(body: (Int) -> Bool)",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: ".myMap(:)",
          insertText: #"""
            ?.myMap(${1:{ ${2:Int} in ${3:Bool} \}})
            """#,
          insertTextFormat: .snippet,
          textEdit: .textEdit(
            TextEdit(
              range: positions["1️⃣"]..<positions["2️⃣"],
              newText: #"""
                ?.myMap(${1:{ ${2:Int} in ${3:Bool} \}})
                """#
            )
          )
        )
      ]
    )
  }

  func testExpandMultipleClosurePlaceholders() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct MyArray {
          func myMap(_ body: (Int) -> Bool, _ second: (Int) -> String) {}
      }
      func test(x: MyArray) {
          x.1️⃣
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(
      completions.items.clearingUnstableValues.filter { $0.label.contains("myMap") },
      [
        CompletionItem(
          label: "myMap(body: (Int) -> Bool, second: (Int) -> String)",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "myMap(::)",
          insertText: #"""
            myMap(${1:{ ${2:Int} in ${3:Bool} \}}, ${4:{ ${5:Int} in ${6:String} \}})
            """#,
          insertTextFormat: .snippet,
          textEdit: .textEdit(
            TextEdit(
              range: Range(positions["1️⃣"]),
              newText: #"""
                myMap(${1:{ ${2:Int} in ${3:Bool} \}}, ${4:{ ${5:Int} in ${6:String} \}})
                """#
            )
          )
        )
      ]
    )
  }

  func testExpandMultipleClosurePlaceholdersWithLabel() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct MyArray {
          func myMap(_ body: (Int) -> Bool, second: (Int) -> String) {}
      }
      func test(x: MyArray) {
          x.1️⃣
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(
      completions.items.clearingUnstableValues.filter { $0.label.contains("myMap") },
      [
        CompletionItem(
          label: "myMap(body: (Int) -> Bool, second: (Int) -> String)",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "myMap(:second:)",
          insertText: #"""
            myMap(${1:{ ${2:Int} in ${3:Bool} \}}, second: ${4:{ ${5:Int} in ${6:String} \}})
            """#,
          insertTextFormat: .snippet,
          textEdit: .textEdit(
            TextEdit(
              range: Range(positions["1️⃣"]),
              newText: #"""
                myMap(${1:{ ${2:Int} in ${3:Bool} \}}, second: ${4:{ ${5:Int} in ${6:String} \}})
                """#
            )
          )
        )
      ]
    )
  }

  func testInferIndentationWhenExpandingClosurePlaceholder() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct MyArray {
        func myMap(_ body: (Int) -> Bool) -> Int {
          return 1
        }
      }
      func test(x: MyArray) {
        x.1️⃣
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(
      completions.items.filter { $0.label.contains("myMap") }.clearingUnstableValues,
      [
        CompletionItem(
          label: "myMap(body: (Int) -> Bool)",
          kind: .method,
          detail: "Int",
          deprecated: false,
          filterText: "myMap(:)",
          insertText: #"""
            myMap(${1:{ ${2:Int} in ${3:Bool} \}})
            """#,
          insertTextFormat: .snippet,
          textEdit: .textEdit(
            TextEdit(
              range: Range(positions["1️⃣"]),
              newText: #"""
                myMap(${1:{ ${2:Int} in ${3:Bool} \}})
                """#
            )
          )
        )
      ]
    )
  }

  func testCompletionScoring() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct Foo {
        func makeBool() -> Bool { true }
        func makeInt() -> Int { 1 }
        func makeString() -> String { "" }
      }
      func test(foo: Foo) {
        let x: Int = foo.make1️⃣
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(
      completions.items.clearingUnstableValues.map(\.label),
      ["makeInt()", "makeBool()", "makeString()"]
    )
  }

  func testCompletionItemResolve() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let capabilities = ClientCapabilities(
      textDocument: TextDocumentClientCapabilities(
        completion: TextDocumentClientCapabilities.Completion(
          completionItem: TextDocumentClientCapabilities.Completion.CompletionItem(
            resolveSupport: TextDocumentClientCapabilities.Completion.CompletionItem.ResolveSupportProperties(
              properties: ["documentation"]
            )
          )
        )
      )
    )

    let testClient = try await TestSourceKitLSPClient(capabilities: capabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct Foo {
        /// Creates a true value
        func makeBool() -> Bool { true }
      }
      func test(foo: Foo) {
        foo.make1️⃣
      }
      """,
      uri: uri
    )
    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let item = try XCTUnwrap(completions.items.only)
    XCTAssertNil(item.documentation)
    let resolvedItem = try await testClient.send(CompletionItemResolveRequest(item: item))
    XCTAssertEqual(
      resolvedItem.documentation,
      .markupContent(MarkupContent(kind: .markdown, value: "Creates a true value"))
    )
  }

  func testCallDefaultedArguments() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct Foo {
        func makeBool(value: Bool = true) -> Bool { value }
      }
      func test(foo: Foo) {
        foo.make1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(completions.items.map(\.insertText), ["makeBool()", "makeBool(value: )"])
  }
}

private func countFs(_ response: CompletionList) -> Int {
  return response.items.filter { $0.label.hasPrefix("f") }.count
}

fileprivate extension Position {
  func adding(columns: Int) -> Position {
    return Position(line: line, utf16index: utf16index + columns)
  }
}
