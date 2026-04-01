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

final class SyntaxCodeActionScopeAccessorTests: SourceKitLSPTestCase {
  func testCursorInfoAccessorIntegration() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣let count = [1, 2, 3, 4, 5]
      count.forEach { element in
        print(element)
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

  func testCursorInfoAccessorReturnsNilWhenUnavailable() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣func simple() {
        return
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

  func testCursorInfoAccessorIsAsync() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣let value = 42
      """,
      uri: uri
    )

    async let codeActionsTask = testClient.send(
      CodeActionRequest(
        range: positions["1️⃣"]..<positions["1️⃣"],
        context: .init(),
        textDocument: TextDocumentIdentifier(uri)
      )
    )

    let codeActions = try await codeActionsTask
    XCTAssertNotNil(codeActions)
  }

  func testMultipleProvidersAccessCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣struct Example {
        2️⃣var name: String
        3️⃣var value: Int
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

    let actions1 = try await req1
    let actions2 = try await req2
    let actions3 = try await req3

    XCTAssertNotNil(actions1)
    XCTAssertNotNil(actions2)
    XCTAssertNotNil(actions3)
  }

  func testCursorInfoAccessorWithIntegerLiterals() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣let binary = 0b1010
      let octal = 0o755
      let hex = 0xFF
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
