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

    guard let ifItem = completions.items.first(where: { $0.label == "if" }) else {
      XCTFail("No completion item with label 'if'")
      return
    }

    XCTAssertEqual(ifItem.kind, .keyword)
    XCTAssertEqual(ifItem.insertTextFormat, .snippet)

    guard let insertText = ifItem.insertText else {
      XCTFail("Completion item for 'if' has no insertText")
      return
    }
    XCTAssertTrue(insertText.contains("${1:condition}"))
    XCTAssertTrue(insertText.contains("${0:"))
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

    guard let forItem = completions.items.first(where: { $0.label == "for" }) else {
      XCTFail("No completion item with label 'for'")
      return
    }

    XCTAssertEqual(forItem.kind, .keyword)
    XCTAssertEqual(forItem.insertTextFormat, .snippet)

    guard let insertText = forItem.insertText else {
      XCTFail("Completion item for 'for' has no insertText")
      return
    }
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

    guard let whileItem = completions.items.first(where: { $0.label == "while" }) else {
      XCTFail("No completion item with label 'while'")
      return
    }

    XCTAssertEqual(whileItem.kind, .keyword)
    XCTAssertEqual(whileItem.insertTextFormat, .snippet)

    guard let insertText = whileItem.insertText else {
      XCTFail("Completion item for 'while' has no insertText")
      return
    }
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

    guard let guardItem = completions.items.first(where: { $0.label == "guard" }) else {
      XCTFail("No completion item with label 'guard'")
      return
    }

    XCTAssertEqual(guardItem.kind, .keyword)
    XCTAssertEqual(guardItem.insertTextFormat, .snippet)

    guard let insertText = guardItem.insertText else {
      XCTFail("Completion item for 'guard' has no insertText")
      return
    }
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

    guard let switchItem = completions.items.first(where: { $0.label == "switch" }) else {
      XCTFail("No completion item with label 'switch'")
      return
    }

    XCTAssertEqual(switchItem.kind, .keyword)
    XCTAssertEqual(switchItem.insertTextFormat, .snippet)

    guard let insertText = switchItem.insertText else {
      XCTFail("Completion item for 'switch' has no insertText")
      return
    }
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

    guard let repeatItem = completions.items.first(where: { $0.label == "repeat" }) else {
      XCTFail("No completion item with label 'repeat'")
      return
    }

    XCTAssertEqual(repeatItem.kind, .keyword)
    XCTAssertEqual(repeatItem.insertTextFormat, .snippet)

    guard let insertText = repeatItem.insertText else {
      XCTFail("Completion item for 'repeat' has no insertText")
      return
    }
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

    guard let ifItem = completions.items.first(where: { $0.label == "if" }) else {
      XCTFail("No completion item with label 'if'")
      return
    }

    XCTAssertEqual(ifItem.kind, .keyword)
    XCTAssertEqual(ifItem.insertTextFormat, .plain)
    XCTAssertEqual(ifItem.insertText, "if")
  }
}
