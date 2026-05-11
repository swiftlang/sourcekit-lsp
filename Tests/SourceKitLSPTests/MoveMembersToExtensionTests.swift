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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
@_spi(Testing) import SwiftLanguageService
import SwiftParser
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
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
  documentCapabilities.completion = .init(completionItem: .init(snippetSupport: true))
  return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
}()

final class MoveMembersToExtensionTests: SourceKitLSPTestCase {
  func testMoveMembersToExtension() async throws {
    try await assertMoveMembersToExtensionCodeAction(
      """
      1️⃣class Foo {
        2️⃣func foo() {
          print("Hello world!")
        }3️⃣

        func bar() {
          print("Hello world!")
        }
      }4️⃣
      """,
      expected:
        """
        class Foo {
          func bar() {
            print("Hello world!")
          }
        }

        extension Foo {
          func foo() {
            print("Hello world!")
          }
        }
        """
    )
  }

  func testMoveParticiallySelectedFunctionFromClass() async throws {
    try await assertMoveMembersToExtensionCodeAction(
      """
      1️⃣class Foo {
        func foo() {
          print("Hello world!")
        }

        func bar() {
          2️⃣print("Hello world!")
        }3️⃣
      }

      struct Bar {
        func foo() {}
      }4️⃣
      """,
      expected:
        """
        class Foo {
          func foo() {
            print("Hello world!")
          }
        }

        extension Foo {
          func bar() {
            print("Hello world!")
          }
        }

        struct Bar {
          func foo() {}
        }
        """
    )
  }

  func testMoveSelectedFromClass() async throws {
    try await assertMoveMembersToExtensionCodeAction(
      """
      1️⃣class Foo {2️⃣
        func foo() {
          print("Hello world!")
        }

        deinit() {}

        func bar() {
          print("Hello world!")
        }3️⃣
      }

      struct Bar {
        func foo() {}
      }4️⃣
      """,
      expected:
        """
        class Foo {
          deinit() {}
        }

        extension Foo {
          func foo() {
            print("Hello world!")
          }

          func bar() {
            print("Hello world!")
          }
        }

        struct Bar {
          func foo() {}
        }
        """
    )
  }

  func testMoveNestedFromStruct() async throws {
    try await assertMoveMembersToExtensionCodeAction(
      """
      1️⃣struct Outer {2️⃣
        struct Inner {
          func moveThis() {}
        }3️⃣
      }4️⃣
      """,
      expected:
        """
        struct Outer {}

        extension Outer {
          struct Inner {
            func moveThis() {}
          }
        }
        """
    )
  }

  func testMoveNestedFromStruct2() async throws {
    try await assertMoveMembersToExtensionCodeAction(
      """
      1️⃣struct Outer<T> {2️⃣
        struct Inner {
          func moveThis() {}
        }3️⃣
      }4️⃣
      """,
      expected:
        """
        struct Outer<T> {}

        extension Outer {
          struct Inner {
            func moveThis() {}
          }
        }
        """
    )
  }

  func testMoveSelectedFunctionName() async throws {
    try await assertMoveMembersToExtensionCodeAction(
      """
      1️⃣struct Outer<T> {
        struct Inner {
          func 2️⃣moveThis()3️⃣ {}
        }
      }4️⃣
      """,
      expected:
        """
        struct Outer<T> {}

        extension Outer {
          struct Inner {
            func moveThis() {}
          }
        }
        """
    )
  }

  func testSelectedDeinitializerMember() async throws {
    let source = """
      1️⃣class Foo {
        func foo() {
          print("Hello world!")
        }

      2️⃣deinit() {}3️⃣

        func bar() {
          print("Hello world!")
        }
      }

      struct Bar {
        func foo() {}
      }4️⃣
      """

    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(source, uri: uri)

    let request = CodeActionRequest(
      range: positions["2️⃣"]..<positions["3️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )

    let result = try await testClient.send(request)

    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions")
      return
    }

    XCTAssertTrue(codeActions.count == 1)
  }

  func testMoveEmptySelection() async throws {
    let source = """
      1️⃣class Foo {
        func foo() {
          print("Hello world!")
        }

      2️⃣3️⃣

        func bar() {
          print("Hello world!")
        }
      }

      struct Bar {
        func foo() {}
      }4️⃣
      """

    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(source, uri: uri)

    let request = CodeActionRequest(
      range: positions["2️⃣"]..<positions["3️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )

    let result = try await testClient.send(request)

    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions")
      return
    }

    XCTAssertFalse(
      codeActions.contains(where: { $0.title == "Move to extension" }),
      "\"Move to extension\" should not be offered for an empty selection. Got: \(codeActions.map(\.title))"
    )
  }

  private func assertMoveMembersToExtensionCodeAction(
    _ source: String,
    expected: String,
  ) async throws {
    let testClient = try await TestSourceKitLSPClient(capabilities: clientCapabilitiesWithCodeActionSupport)
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(source, uri: uri)

    let request = CodeActionRequest(
      range: positions["2️⃣"]..<positions["3️⃣"],
      context: .init(),
      textDocument: TextDocumentIdentifier(uri)
    )
    let result = try await testClient.send(request)

    guard case .codeActions(let codeActions) = result else {
      XCTFail("Expected code actions")
      return
    }

    let expectedCodeAction = CodeAction(
      title: "Move to extension",
      kind: .refactorInline,
      diagnostics: nil,
      edit: WorkspaceEdit(
        changes: [
          uri: [
            TextEdit(
              range: positions["1️⃣"]..<positions["4️⃣"],
              newText: expected
            )
          ]
        ]
      ),
      command: nil
    )

    XCTAssertTrue(codeActions.contains(expectedCodeAction))
  }
}
