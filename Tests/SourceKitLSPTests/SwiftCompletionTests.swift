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

import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import XCTest

final class SwiftCompletionTests: XCTestCase {

  private typealias CompletionCapabilities = TextDocumentClientCapabilities.Completion

  /// Base document text to use for completion tests.
  private let text: String = """
    struct S {
      /// Documentation for `abc`.
      var abc: Int

      func test(a: Int) {
        self.abc
      }

      func test(_ b: Int) {
        self.abc
      }
    }
    """

  // MARK: - Helpers

  private func initializeServer(
    options: SKCompletionOptions = .init(),
    capabilities: CompletionCapabilities? = nil
  ) async throws -> TestSourceKitLSPClient {
    let testClient = TestSourceKitLSPClient()
    var documentCapabilities: TextDocumentClientCapabilities?
    if let capabilities = capabilities {
      documentCapabilities = TextDocumentClientCapabilities()
      documentCapabilities?.completion = capabilities
    } else {
      documentCapabilities = nil
    }
    _ = try await testClient.send(
      InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
        initializationOptions: .dictionary([
          "completion": .dictionary([
            "maxResults": options.maxResults == nil ? .null : .int(options.maxResults!)
          ])
        ]),
        capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
        trace: .off,
        workspaceFolders: nil
      )
    )
    return testClient
  }

  // MARK: - Tests

  func testCompletionServerFilter() async throws {
    try await testCompletionBasic(options: SKCompletionOptions(maxResults: nil))
  }

  func testCompletionDefaultFilter() async throws {
    try await testCompletionBasic(options: SKCompletionOptions())
  }

  func testCompletionBasic(options: SKCompletionOptions) async throws {
    let testClient = try await initializeServer(options: options)
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(text, uri: uri)

    let selfDot = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 5, utf16index: 9)
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
      XCTAssertEqual(
        abc.textEdit,
        .textEdit(TextEdit(range: Position(line: 5, utf16index: 9)..<Position(line: 5, utf16index: 9), newText: "abc"))
      )
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .plain)
    }

    for col in 10...12 {
      let inIdent = try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 5, utf16index: col)
        )
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
      XCTAssertEqual(
        abc.textEdit,
        .textEdit(
          TextEdit(range: Position(line: 5, utf16index: 9)..<Position(line: 5, utf16index: col), newText: "abc")
        )
      )
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .plain)
    }

    let after = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 6, utf16index: 0)
      )
    )
    XCTAssertNotEqual(after, selfDot)
  }

  func testCompletionSnippetSupport() async throws {
    var capabilities = CompletionCapabilities()
    capabilities.completionItem = CompletionCapabilities.CompletionItem(snippetSupport: true)

    let testClient = try await initializeServer(capabilities: capabilities)
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(text, uri: uri)

    func getTestMethodCompletion(_ position: Position, label: String) async throws -> CompletionItem? {
      let selfDot = try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: position
        )
      )
      return selfDot.items.first { $0.label == label }
    }

    var test = try await getTestMethodCompletion(Position(line: 5, utf16index: 9), label: "test(a: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
      XCTAssertEqual(
        test.textEdit,
        .textEdit(
          TextEdit(
            range: Position(line: 5, utf16index: 9)..<Position(line: 5, utf16index: 9),
            newText: "test(a: ${1:Int})"
          )
        )
      )
      XCTAssertEqual(test.insertText, "test(a: ${1:Int})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }

    test = try await getTestMethodCompletion(Position(line: 9, utf16index: 9), label: "test(b: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(:)")
      XCTAssertEqual(
        test.textEdit,
        .textEdit(
          TextEdit(
            range: Position(line: 9, utf16index: 9)..<Position(line: 9, utf16index: 9),
            newText: "test(${1:b: Int})"
          )
        )
      )
      XCTAssertEqual(test.insertText, "test(${1:b: Int})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }
  }

  func testCompletionNoSnippetSupport() async throws {
    var capabilities = CompletionCapabilities()
    capabilities.completionItem?.snippetSupport = false
    let testClient = try await initializeServer(capabilities: capabilities)
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(text, uri: uri)

    func getTestMethodCompletion(_ position: Position, label: String) async throws -> CompletionItem? {
      let selfDot = try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: position
        )
      )
      return selfDot.items.first { $0.label == label }
    }

    var test = try await getTestMethodCompletion(Position(line: 5, utf16index: 9), label: "test(a: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
      XCTAssertEqual(
        test.textEdit,
        .textEdit(
          TextEdit(range: Position(line: 5, utf16index: 9)..<Position(line: 5, utf16index: 9), newText: "test(a: )")
        )
      )
      XCTAssertEqual(test.insertText, "test(a: )")
      XCTAssertEqual(test.insertTextFormat, .plain)
    }

    test = try await getTestMethodCompletion(Position(line: 9, utf16index: 9), label: "test(b: Int)")
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(:)")
      // FIXME:
      XCTAssertEqual(
        test.textEdit,
        .textEdit(
          TextEdit(range: Position(line: 9, utf16index: 9)..<Position(line: 9, utf16index: 9), newText: "test()")
        )
      )
      XCTAssertEqual(test.insertText, "test()")
      XCTAssertEqual(test.insertTextFormat, .plain)
    }
  }

  func testCompletionPositionServerFilter() async throws {
    let testClient = try await initializeServer(options: SKCompletionOptions(maxResults: nil))
    let uri = DocumentURI.for(.swift)
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
    let testClient = try await initializeServer()
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(
      """
      struct Foo {
        let bar: Int
      }
      let a: Foo? = Foo(bar: 1)
      a.ba
      """,
      uri: uri
    )

    for col in 2...4 {
      let response = try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 4, utf16index: col)
        )
      )

      guard let item = response.items.first(where: { $0.label.contains("bar") }) else {
        XCTFail("No completion item with label 'bar'")
        return
      }
      XCTAssertEqual(item.filterText, ".bar")
      XCTAssertEqual(
        item.textEdit,
        .textEdit(
          TextEdit(range: Position(line: 4, utf16index: 1)..<Position(line: 4, utf16index: col), newText: "?.bar")
        )
      )
    }
  }

  func testCompletionOverride() async throws {
    let testClient = try await initializeServer()
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(
      """
      class Base {
        func foo() {}
      }
      class C: Base {
        func    // don't delete trailing space in this file
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 4, utf16index: 7)
      )
    )
    guard let item = response.items.first(where: { $0.label == "foo()" }) else {
      XCTFail("No completion item with label 'foo()'")
      return
    }
    // FIXME: should be "foo()"
    XCTAssertEqual(item.filterText, "func foo()")
    XCTAssertEqual(
      item.textEdit,
      .textEdit(
        TextEdit(
          range: Position(line: 4, utf16index: 2)..<Position(line: 4, utf16index: 7),
          newText: "override func foo() {\n\n}"
        )
      )
    )
  }

  func testCompletionOverrideInNewLine() async throws {
    let testClient = try await initializeServer()
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(
      """
      class Base {
        func foo() {}
      }
      class C: Base {
        func
          // don't delete trailing space in this file
      }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 5, utf16index: 2)
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
      .textEdit(
        TextEdit(
          range: Position(line: 5, utf16index: 2)..<Position(line: 5, utf16index: 2),
          newText: "override func foo() {\n\n}"
        )
      )
    )
  }

  func testMaxResults() async throws {
    let testClient = try await initializeServer(options: SKCompletionOptions(maxResults: nil))
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(
      """
      struct S {
        func f1() {}
        func f2() {}
        func f3() {}
        func f4() {}
        func f5() {}
        func test() {
          self.f
        }
      }
      """,
      uri: uri
    )

    // Server-wide option
    assertEqual(
      5,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: Position(line: 7, utf16index: 9)
          )
        )
      )
    )

    // Explicit option
    assertEqual(
      5,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: Position(line: 7, utf16index: 9),
            sourcekitlspOptions: SKCompletionOptions(maxResults: nil)
          )
        )
      )
    )

    // MARK: Limited

    assertEqual(
      5,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: Position(line: 7, utf16index: 9),
            sourcekitlspOptions: SKCompletionOptions(maxResults: 1000)
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
            position: Position(line: 7, utf16index: 9),
            sourcekitlspOptions: SKCompletionOptions(maxResults: 3)
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
            position: Position(line: 7, utf16index: 9),
            sourcekitlspOptions: SKCompletionOptions(maxResults: 1)
          )
        )
      )
    )

    // 0 also means unlimited
    assertEqual(
      5,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: Position(line: 7, utf16index: 9),
            sourcekitlspOptions: SKCompletionOptions(maxResults: 0)
          )
        )
      )
    )

    // MARK: With filter='f'

    assertEqual(
      5,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: Position(line: 7, utf16index: 10),
            sourcekitlspOptions: SKCompletionOptions(maxResults: nil)
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
            position: Position(line: 7, utf16index: 10),
            sourcekitlspOptions: SKCompletionOptions(maxResults: 3)
          )
        )
      )
    )

  }

  func testRefilterAfterIncompleteResults() async throws {
    let testClient = try await initializeServer(options: SKCompletionOptions(maxResults: 20))
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(
      """
      struct S {
        func fooAbc() {}
        func fooBcd() {}
        func fooCde() {}
        func fooDef() {}
        func fooGoop() {}
        func test() {
          self.fcdez
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
            position: Position(line: 7, utf16index: 10),
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
            position: Position(line: 7, utf16index: 11),
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
            position: Position(line: 7, utf16index: 12),
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
            position: Position(line: 7, utf16index: 13),
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
            position: Position(line: 7, utf16index: 14),
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
            position: Position(line: 7, utf16index: 12),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    // Not valid for the current session.
    // We explicitly keep the session and fail any requests that don't match so that the editor
    // can rely on `.triggerFromIncompleteCompletions` always being fast.
    await assertThrowsError(
      try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 7, utf16index: 0),
          context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
        )
      )
    )
    assertEqual(
      1,
      countFs(
        try await testClient.send(
          CompletionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: Position(line: 7, utf16index: 13),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    // Trigger kind changed => OK (20 is maxResults since we're outside the member completion)
    assertEqual(
      20,
      try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 7, utf16index: 0),
          context: CompletionContext(triggerKind: .invoked)
        )
      ).items.count
    )
  }

  func testRefilterAfterIncompleteResultsWithEdits() async throws {
    let testClient = try await initializeServer(options: SKCompletionOptions(maxResults: nil))
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(
      """
      struct S {
        func fooAbc() {}
        func fooBcd() {}
        func fooCde() {}
        func fooDef() {}
        func fooGoop() {}
        func test() {
          self.fz
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
            position: Position(line: 7, utf16index: 10),
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
            position: Position(line: 7, utf16index: 11),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: Position(line: 7, utf16index: 10)..<Position(line: 7, utf16index: 11), text: "A ")
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
            position: Position(line: 7, utf16index: 11),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    // 'fA '
    await assertThrowsError(
      try await testClient.send(
        CompletionRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: Position(line: 7, utf16index: 12),
          context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
        )
      )
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: Position(line: 7, utf16index: 10)..<Position(line: 7, utf16index: 11), text: "Ab")
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
            position: Position(line: 7, utf16index: 11),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: Position(line: 7, utf16index: 10)..<Position(line: 7, utf16index: 11), text: "")
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
            position: Position(line: 7, utf16index: 11),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
        contentChanges: [
          .init(range: Position(line: 7, utf16index: 11)..<Position(line: 7, utf16index: 11), text: "d")
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
            position: Position(line: 7, utf16index: 12),
            context: CompletionContext(triggerKind: .triggerFromIncompleteCompletions)
          )
        )
      )
    )
  }

  /// Regression test for https://bugs.swift.org/browse/SR-13561 to make sure the a session
  /// close waits for its respective open to finish to prevent a session geting stuck open.
  func testSessionCloseWaitsforOpen() async throws {
    let testClient = try await initializeServer(options: SKCompletionOptions(maxResults: nil))
    let uri = DocumentURI.for(.swift)
    testClient.openDocument(
      """
      struct S {
        func forSomethingCrazy() {}
        func forSomethingCool() {}
        func test() {
          self.forSome
        }
        func print() {}
        func anotherOne() {
          self.prin
        }
      }
      """,
      uri: uri
    )

    let forSomeComplete = CompletionRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: Position(line: 4, utf16index: 12),  // forS^
      context: CompletionContext(triggerKind: .invoked)
    )
    let printComplete = CompletionRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: Position(line: 8, utf16index: 12),  // prin^
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
}

private func countFs(_ response: CompletionList) -> Int {
  return response.items.filter { $0.label.hasPrefix("f") }.count
}
