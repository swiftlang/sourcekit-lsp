//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
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

final class ForEachToForInCodeActionTests: SourceKitLSPTestCase {

  func testBasicForEachToForInConversion() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNotNil(forEachAction, "Should offer 'Convert to for-in loop' action")
  }

  func testRejectsCustomForEach() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      struct MyCollection {
        func forEach(_ closure: (Int) -> Void) {
          closure(1)
        }
      }

      let col = MyCollection()
      1️⃣col.forEach { item in
        print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNil(forEachAction, "Should NOT offer action for custom forEach (not stdlib)")
  }

  func testExplicitClosureArgument() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach({ item in
        print(item)
      })
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNotNil(forEachAction, "Should offer action for explicit closure argument form")
  }

  func testRejectsShorthandDollarZero() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { print($0) }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNil(forEachAction, "Should NOT offer action for $0 shorthand")
  }

  func testRejectsReturnWithValue() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        if item > 2 {
          return 42
        }
        print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNil(forEachAction, "Should NOT offer action when closure has return with value")
  }

  func testTransformsBareReturnToContinue() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        if item < 2 {
          return
        }
        print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNotNil(forEachAction, "Bare return should be converted to continue")
  }

  func testRejectsClosureWithTry() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        try print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNil(forEachAction, "Should NOT offer action for try expression")
  }

  func testRejectsClosureWithAwait() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        await print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }
    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNil(forEachAction, "Should NOT offer action for await expression")
  }

  func testGracefulDegradationWithoutCursorInfo() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let array = [1, 2, 3]
      1️⃣array.forEach { item in
        print(item)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    XCTAssertNotNil(result, "Code action request should complete even if cursorInfo unavailable")
  }

  func testProviderIntegrationInCodeActionFlow() async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      let numbers = [1, 2, 3, 4, 5]
      1️⃣numbers.forEach { n in
        print(n)
      }
      """,
      uri: uri
    )

    let request = CodeActionRequest(
      range: positions["1️⃣"]..<positions["1️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)
    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions response")
      return
    }

    let forEachAction = codeActions.first(where: { $0.title == "Convert to 'for-in' loop" })
    XCTAssertNotNil(forEachAction, "Provider should be called and return action")
  }
}
