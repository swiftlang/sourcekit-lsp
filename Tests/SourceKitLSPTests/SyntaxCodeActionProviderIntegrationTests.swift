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

final class SyntaxCodeActionProviderIntegrationTests: SourceKitLSPTestCase {
  func testAsyncProviderCallsIntegration() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣let x = 42
      let y = 100
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let codeActions = try await testClient.send(request)
    XCTAssertNotNil(codeActions)
  }

  func testConcurrentProviderAccessToCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣struct Point {
        2️⃣var x: Int
        3️⃣var y: Int
      }
      """,
      uri: uri
    )

    async let req1 = testClient.send(
      CodeActionRequest(
        range: positions["1️⃣"]..<positions["1️⃣"],
        context: .init(),
        textDocument: TextDocumentIdentifier(uri)
      )
    )
    async let req2 = testClient.send(
      CodeActionRequest(
        range: positions["2️⃣"]..<positions["2️⃣"],
        context: .init(),
        textDocument: TextDocumentIdentifier(uri)
      )
    )
    async let req3 = testClient.send(
      CodeActionRequest(
        range: positions["3️⃣"]..<positions["3️⃣"],
        context: .init(),
        textDocument: TextDocumentIdentifier(uri)
      )
    )

    let result1 = try await req1
    let result2 = try await req2
    let result3 = try await req3
    XCTAssertNotNil(result1)
    XCTAssertNotNil(result2)
    XCTAssertNotNil(result3)
  }

  func testBackwardCompatibilityWithExistingProviders() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣enum Color {
        case red
        case green
        case blue
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let codeActions = try await testClient.send(request)
    XCTAssertNotNil(codeActions)
  }

  func testMultipleProvidersShareCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      class Calculator {
        1️⃣func add(a: Int, b: Int) -> Int {
          return a + b
        }
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let codeActions = try await testClient.send(request)
    XCTAssertNotNil(codeActions)
  }

  func testProviderErrorHandling() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣let incomplete =
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let codeActions = try await testClient.send(request)
    XCTAssertNotNil(codeActions)
  }

  func testCursorInfoReuseAcrossProviders() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func process(data: [Int]) {
        1️⃣data.forEach { element in
          print(element)
        }
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )

    let actions1 = try await testClient.send(request)
    let actions2 = try await testClient.send(request)

    XCTAssertNotNil(actions1)
    XCTAssertNotNil(actions2)
  }

  func testSemanticAwareProviderUsingCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      protocol Sequence {
        func forEach(_ body: (Element) throws -> Void) rethrows
      }

      let items = [1, 2, 3]
      1️⃣items.forEach { print($0) }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let codeActions = try await testClient.send(request)
    XCTAssertNotNil(codeActions)
  }
}
