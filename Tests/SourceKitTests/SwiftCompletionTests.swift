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
import SKSupport
import SKTestSupport
import XCTest

@testable import SourceKit

final class SwiftCompletionTests: XCTestCase {

  typealias CompletionCapabilities = TextDocumentClientCapabilities.Completion

  /// Base document text to use for completion tests.
  let text: String = """
    struct S {
      var abc: Int

      func test(a: Int) {
        self.abc
      }
    }
    """

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  var workspace: Workspace! = nil

  override func tearDown() {
    shutdownServer()
  }

  func shutdownServer() {
    workspace = nil
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
      rootURL: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))

    workspace = connection.server!.workspace!
  }

  func openDocument(text: String? = nil, url: URL) {
    sk.allowUnexpectedNotification = true
    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: text ?? self.text)))
  }

  func testCompletion() {
    initializeServer()
    let url = URL(fileURLWithPath: "/a.swift")
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
      // FIXME:
      XCTAssertNil(abc.textEdit)
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .plain)
    }

    for col in 10...12 {
      let inIdent = try! sk.sendSync(CompletionRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 4, utf16index: col)))
      // If we switch to server-side filtering this will change.
      XCTAssertEqual(inIdent, selfDot)
    }

    let after = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 4, utf16index: 13)))
    XCTAssertNotEqual(after, selfDot)
  }

  func testCompletionSnippetSupport() {
    var capabilities = CompletionCapabilities()
    capabilities.completionItem = CompletionCapabilities.CompletionItem(snippetSupport: true)

    initializeServer(capabilities: capabilities)
    let url = URL(fileURLWithPath: "/a.swift")
    openDocument(url: url)

    func getTestMethodCompletion() -> CompletionItem? {
      let selfDot = try! sk.sendSync(CompletionRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 4, utf16index: 9)))
      return selfDot.items.first { $0.label == "test(a: Int)" }
    }

    var test = getTestMethodCompletion()
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
      // FIXME:
      XCTAssertNil(test.textEdit)
      // FIXME: should be "a" in the placeholder.
      XCTAssertEqual(test.insertText, "test(a: ${1:value})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }

    shutdownServer()
    capabilities.completionItem?.snippetSupport = false
    initializeServer(capabilities: capabilities)
    openDocument(url: url)

    test = getTestMethodCompletion()
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertEqual(test.detail, "Void")
      XCTAssertEqual(test.filterText, "test(a:)")
      // FIXME:
      XCTAssertNil(test.textEdit)
      // FIXME: should be "a" in the placeholder.
      XCTAssertEqual(test.insertText, "test(a: )")
      XCTAssertEqual(test.insertTextFormat, .plain)
    }
  }

  func testCompletionPosition() {
    initializeServer()
    let url = URL(fileURLWithPath: "/a.swift")
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
}
