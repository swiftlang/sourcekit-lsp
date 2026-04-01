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

final class SharedCursorInfoIntegrationTests: SourceKitLSPTestCase {
  func testCodeActionsWithSharedCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣let x = 123
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

  func testCodeActionsGracefulWithoutCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣func test() {
        print("hello")
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

  func testConcurrentCodeActionRequests() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣let count = 5
      2️⃣let value = 10
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

    let actions1 = try await req1
    let actions2 = try await req2

    XCTAssertNotNil(actions1)
    XCTAssertNotNil(actions2)
  }

  func testBackwardCompatibilityWithoutCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      1️⃣struct MyStruct {
        var value: Int
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
}
