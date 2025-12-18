//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import XCTest

final class SwiftCompletionSnippetTests: SourceKitLSPTestCase {
  private var snippetCapabilities = ClientCapabilities(
    textDocument: TextDocumentClientCapabilities(
      completion: TextDocumentClientCapabilities.Completion(
        completionItem: TextDocumentClientCapabilities.Completion.CompletionItem(snippetSupport: true)
      )
    )
  )

  func testKeywordIfProvidesSnippet() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let ifItem = try XCTUnwrap(completions.items.first(where: { $0.label == "if" }))

    XCTAssertEqual(ifItem.kind, .keyword)
    XCTAssertEqual(ifItem.insertTextFormat, .snippet)

    let insertText = try XCTUnwrap(ifItem.insertText)
    XCTAssertTrue(insertText.contains("${1:condition}"))
    XCTAssertTrue(insertText.contains("${0:}"))
  }

  func testKeywordForProvidesSnippet() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let forItem = try XCTUnwrap(completions.items.first(where: { $0.label == "for" }))

    XCTAssertEqual(forItem.kind, .keyword)
    XCTAssertEqual(forItem.insertTextFormat, .snippet)

    let insertText = try XCTUnwrap(forItem.insertText)
    XCTAssertTrue(insertText.contains("${1:item}"))
    XCTAssertTrue(insertText.contains("${2:sequence}"))
  }

  func testKeywordWhileProvidesSnippet() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let whileItem = try XCTUnwrap(completions.items.first(where: { $0.label == "while" }))

    XCTAssertEqual(whileItem.kind, .keyword)
    XCTAssertEqual(whileItem.insertTextFormat, .snippet)

    let insertText = try XCTUnwrap(whileItem.insertText)
    XCTAssertTrue(insertText.contains("${1:condition}"))
  }

  func testKeywordGuardProvidesSnippet() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let guardItem = try XCTUnwrap(completions.items.first(where: { $0.label == "guard" }))

    XCTAssertEqual(guardItem.kind, .keyword)
    XCTAssertEqual(guardItem.insertTextFormat, .snippet)

    let insertText = try XCTUnwrap(guardItem.insertText)
    XCTAssertTrue(insertText.contains("${1:condition}"))
    XCTAssertTrue(insertText.contains("else"))
  }

  func testKeywordSwitchProvidesSnippet() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let switchItem = try XCTUnwrap(completions.items.first(where: { $0.label == "switch" }))

    XCTAssertEqual(switchItem.kind, .keyword)
    XCTAssertEqual(switchItem.insertTextFormat, .snippet)

    let insertText = try XCTUnwrap(switchItem.insertText)
    XCTAssertTrue(insertText.contains("${1:value}"))
    XCTAssertTrue(insertText.contains("case"))
  }

  func testKeywordRepeatProvidesSnippet() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let repeatItem = try XCTUnwrap(completions.items.first(where: { $0.label == "repeat" }))

    XCTAssertEqual(repeatItem.kind, .keyword)
    XCTAssertEqual(repeatItem.insertTextFormat, .snippet)

    let insertText = try XCTUnwrap(repeatItem.insertText)
    XCTAssertTrue(insertText.contains("while"))
  }

  func testKeywordWithoutSnippetSupport() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    // Client without snippet support should get plain keywords
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let ifItem = try XCTUnwrap(completions.items.first(where: { $0.label == "if" }))

    XCTAssertEqual(ifItem.kind, .keyword)
    XCTAssertEqual(ifItem.insertTextFormat, .plain)
    XCTAssertEqual(ifItem.insertText, "if")
  }

  func testInsertTextAndTextEditAreConsistent() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    for item in completions.items {
      guard let insertText = item.insertText else { continue }
      // Skip SourceKit's implicit method call labels (e.g. "funcName()")
      if item.label.contains("(") && item.label.contains(")") { continue }

      if case .textEdit(let te) = item.textEdit {
        XCTAssertEqual(insertText, te.newText, "insertText and textEdit.newText differ for item '\(item.label)'")
      }
    }
  }

  func testKeywordSnippetUsesInferredSpacesIndentation() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func test() {
        let a = 1
        let b = 2
        1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let ifItem = try XCTUnwrap(completions.items.first(where: { $0.label == "if" }))
    let insertText = try XCTUnwrap(ifItem.insertText)

    // Expect newline + two spaces before the final placeholder
    XCTAssertTrue(insertText.contains("\n  ${0:}"), "expected two-space indentation in snippet, got: '\(insertText)'")
  }

  func testKeywordSnippetUsesInferredTabsIndentation() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let testClient = try await TestSourceKitLSPClient(capabilities: snippetCapabilities)
    let uri = DocumentURI(for: .swift)
    // Use raw tabs \t for indentation to ensure server picks up Tab style.
    let positions = testClient.openDocument(
      """
      func test() {
      \tlet a = 1
      \tlet b = 2
      \t1️⃣
      }
      """,
      uri: uri
    )

    let completions = try await testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let ifItem = try XCTUnwrap(completions.items.first(where: { $0.label == "if" }))
    let insertText = try XCTUnwrap(ifItem.insertText)
    XCTAssertTrue(insertText.contains("\n\t"), "expected tab indentation in snippet, got: '\(insertText)'")
  }
}
