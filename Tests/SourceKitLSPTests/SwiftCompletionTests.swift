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
import LSPTestSupport
import SKTestSupport
import SourceKitLSP
import XCTest

final class SwiftCompletionTests: XCTestCase {

  typealias CompletionCapabilities = TextDocumentClientCapabilities.Completion

  /// Base document text to use for completion tests.
  let text: String = """
    struct S {
      var abc: Int

      func test(a: Int) {
        self.abc
      }

      func test(_ b: Int) {
        self.abc
      }
    }
    """

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  override func tearDown() {
    shutdownServer()
  }

  func shutdownServer() {
    sk = nil
    connection = nil
  }

  func initializeServer(capabilities: CompletionCapabilities? = nil) {
    connection = TestSourceKitServer()
    sk = connection.client
    var documentCapabilities: TextDocumentClientCapabilities?
    if let capabilities = capabilities {
      documentCapabilities = TextDocumentClientCapabilities()
      documentCapabilities?.completion = capabilities
    } else {
      documentCapabilities = nil
    }
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))
  }

  func openDocument(text: String? = nil, url: URL) {
    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .swift,
      version: 12,
      text: text ?? self.text)))
  }

  func testCompletion() {
    initializeServer()
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    openDocument(url: url)

    let selfDot = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 4, utf16index: 9)))

    XCTAssertEqual(selfDot.isIncomplete, false)
    XCTAssertGreaterThanOrEqual(selfDot.items.count, 2)
    let abc = selfDot.items.first { $0.label == "abc" }
    XCTAssertNotNil(abc)
    if let abc = abc {
      XCTAssertEqual(abc.kind, .property)
      XCTAssertEqual(abc.detail, "Int")
      XCTAssertEqual(abc.filterText, "abc")
      XCTAssertEqual(abc.textEdit, TextEdit(range: Position(line: 4, utf16index: 9)..<Position(line: 4, utf16index: 9), newText: "abc"))
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .plain)
    }

    for col in 10...12 {
      let inIdent = try! sk.sendSync(CompletionRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 4, utf16index: col)))
      guard let abc = inIdent.items.first(where: { $0.label == "abc" }) else {
        XCTFail("No completion item with label 'abc'")
        return
      }

      // If we switch to server-side filtering this will change.
      XCTAssertEqual(abc.kind, .property)
      XCTAssertEqual(abc.detail, "Int")
      XCTAssertEqual(abc.filterText, "abc")
      XCTAssertEqual(abc.textEdit, TextEdit(range: Position(line: 4, utf16index: 9)..<Position(line: 4, utf16index: col), newText: "abc"))
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .plain)
    }

    let after = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 5, utf16index: 0)))
    XCTAssertNotEqual(after, selfDot)
  }

  func testCompletionSnippetSupport() {
    var capabilities = CompletionCapabilities()
    capabilities.completionItem = CompletionCapabilities.CompletionItem(snippetSupport: true)

    initializeServer(capabilities: capabilities)
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    openDocument(url: url)

    func getTestMethodCompletion(_ position: Position, label: String) -> CompletionItem? {
      let selfDot = try! sk.sendSync(CompletionRequest(
        textDocument: TextDocumentIdentifier(url),
        position: position))
      return selfDot.items.first { $0.label == label }
    }

    func getTestMethodACompletion() -> CompletionItem? {
      return getTestMethodCompletion(Position(line: 4, utf16index: 9), label: "test(a: Int)")
    }

    func getTestMethodBCompletion() -> CompletionItem? {
      return getTestMethodCompletion(Position(line: 8, utf16index: 9), label: "test(b: Int)")
    }

    var test = getTestMethodACompletion()
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
        XCTAssertEqual(test.textEdit, TextEdit(range: Position(line: 4, utf16index: 9)..<Position(line: 4, utf16index: 9), newText: "test(a: ${1:Int})"))
      XCTAssertEqual(test.insertText, "test(a: ${1:Int})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }

    test = getTestMethodBCompletion()
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(:)")
      XCTAssertEqual(test.textEdit, TextEdit(range: Position(line: 8, utf16index: 9)..<Position(line: 8, utf16index: 9), newText: "test(${1:b: Int})"))
      XCTAssertEqual(test.insertText, "test(${1:b: Int})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }

    shutdownServer()
    capabilities.completionItem?.snippetSupport = false
    initializeServer(capabilities: capabilities)
    openDocument(url: url)

    test = getTestMethodACompletion()
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
      XCTAssertEqual(test.textEdit, TextEdit(range: Position(line: 4, utf16index: 9)..<Position(line: 4, utf16index: 9), newText: "test(a: )"))
      XCTAssertEqual(test.insertText, "test(a: )")
      XCTAssertEqual(test.insertTextFormat, .plain)
    }

    test = getTestMethodBCompletion()
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(:)")
      // FIXME:
        XCTAssertEqual(test.textEdit, TextEdit(range: Position(line: 8, utf16index: 9)..<Position(line: 8, utf16index: 9), newText: "test()"))
      XCTAssertEqual(test.insertText, "test()")
      XCTAssertEqual(test.insertTextFormat, .plain)
    }
  }

  func testCompletionPosition() {
    initializeServer()
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    openDocument(text: "foo", url: url)

    for col in 0 ... 3 {
      let inOrAfterFoo = try! sk.sendSync(CompletionRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 0, utf16index: col)))
      XCTAssertFalse(inOrAfterFoo.isIncomplete)
      XCTAssertFalse(inOrAfterFoo.items.isEmpty)
    }

    let outOfRange1 = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 0, utf16index: 4)))
    XCTAssertTrue(outOfRange1.isIncomplete)

    let outOfRange2 = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 1, utf16index: 0)))
    XCTAssertTrue(outOfRange2.isIncomplete)
  }

  func testCompletionOptional() {
    initializeServer()
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    let text = """
    struct Foo {
      let bar: Int
    }
    let a: Foo? = Foo(bar: 1)
    a.ba
    """
    openDocument(text: text, url: url)

    for col in 2...4 {
      let response = try! sk.sendSync(CompletionRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 4, utf16index: col)))
      XCTAssertFalse(response.isIncomplete)
      guard let item = response.items.first(where: { $0.label == "bar" }) else {
        XCTFail("No completion item with label 'bar'")
        return
      }
      XCTAssertEqual(item.filterText, ".bar")
      XCTAssertEqual(item.textEdit, TextEdit(range: Position(line: 4, utf16index: 1)..<Position(line: 4, utf16index: col), newText: "?.bar"))
    }
  }

  func testCompletionOverride() {
    initializeServer()
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    let text = """
    class Base {
      func foo() {}
    }
    class C: Base {
      func    // don't delete trailing space in this file
    }
    """
    openDocument(text: text, url: url)

    let response = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 4, utf16index: 6)))
    XCTAssertFalse(response.isIncomplete)
    guard let item = response.items.first(where: { $0.label == "foo()" }) else {
      XCTFail("No completion item with label 'foo()'")
      return
    }
    XCTAssertEqual(item.filterText, "foo()")
    XCTAssertEqual(item.textEdit, TextEdit(range: Position(line: 4, utf16index: 2)..<Position(line: 4, utf16index: 6), newText: "override func foo() {\n\n}"))
  }

  func testCompletionOverrideInNewLine() {
    initializeServer()
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")
    let text = """
    class Base {
      func foo() {}
    }
    class C: Base {
      func
        // don't delete trailing space in this file
    }
    """
    openDocument(text: text, url: url)

    let response = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 5, utf16index: 2)))
    XCTAssertFalse(response.isIncomplete)
    guard let item = response.items.first(where: { $0.label == "foo()" }) else {
      XCTFail("No completion item with label 'foo()'")
      return
    }
    // If the edit would cross multiple lines, we are currently not replacing any text. It's not technically correct but the best we can do.
    XCTAssertEqual(item.filterText, "foo()")
    XCTAssertEqual(item.textEdit, TextEdit(range: Position(line: 5, utf16index: 2)..<Position(line: 5, utf16index: 2), newText: "override func foo() {\n\n}"))
  }
}
