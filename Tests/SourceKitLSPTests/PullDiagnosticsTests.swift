//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import XCTest

final class PullDiagnosticsTests: XCTestCase {
  enum Error: Swift.Error {
    case unexpectedDiagnosticReport
  }

  /// The mock client used to communicate with the SourceKit-LSP server.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var testClient: TestSourceKitLSPClient! = nil

  override func setUp() async throws {
    testClient = TestSourceKitLSPClient()
    _ = try await self.testClient.send(
      InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(
          workspace: nil,
          textDocument: .init(
            codeAction: .init(codeActionLiteralSupport: .init(codeActionKind: .init(valueSet: [.quickFix])))
          )
        ),
        trace: .off,
        workspaceFolders: nil
      )
    )
  }

  override func tearDown() {
    testClient = nil
  }

  // MARK: - Tests

  func performDiagnosticRequest(text: String) async throws -> [Diagnostic] {
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(text, uri: uri)

    let request = DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))

    let report: DocumentDiagnosticReport
    do {
      report = try await testClient.send(request)
    } catch let error as ResponseError where error.message.contains("unknown request: source.request.diagnostics") {
      throw XCTSkip("toolchain does not support source.request.diagnostics request")
    }

    guard case .full(let fullReport) = report else {
      throw Error.unexpectedDiagnosticReport
    }

    return fullReport.items
  }

  func testUnknownIdentifierDiagnostic() async throws {
    let diagnostics = try await performDiagnosticRequest(
      text: """
        func foo() {
          invalid
        }
        """
    )
    XCTAssertEqual(diagnostics.count, 1)
    let diagnostic = try XCTUnwrap(diagnostics.first)
    XCTAssertEqual(diagnostic.range, Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9))
  }

  /// Test that we can get code actions for pulled diagnostics (https://github.com/apple/sourcekit-lsp/issues/776)
  func testCodeActions() async throws {
    let diagnostics = try await performDiagnosticRequest(
      text: """
        protocol MyProtocol {
          func bar()
        }

        struct Test: MyProtocol {}
        """
    )
    XCTAssertEqual(diagnostics.count, 1)
    let diagnostic = try XCTUnwrap(diagnostics.first)
    XCTAssertEqual(diagnostic.range, Position(line: 4, utf16index: 7)..<Position(line: 4, utf16index: 7))
    let note = try XCTUnwrap(diagnostic.relatedInformation?.first)
    XCTAssertEqual(note.location.range, Position(line: 4, utf16index: 7)..<Position(line: 4, utf16index: 7))
    XCTAssertEqual(note.codeActions?.count ?? 0, 1)

    let response = try await testClient.send(
      CodeActionRequest(
        range: note.location.range,
        context: CodeActionContext(
          diagnostics: diagnostics,
          only: [.quickFix],
          triggerKind: .invoked
        ),
        textDocument: TextDocumentIdentifier(note.location.uri)
      )
    )

    guard case .codeActions(let actions) = response else {
      XCTFail("Expected codeActions response")
      return
    }

    XCTAssertEqual(actions.count, 1)
    let action = try XCTUnwrap(actions.first)
    // Allow the action message to be the one before or after
    // https://github.com/apple/swift/pull/67909, ensuring this test passes with
    // a sourcekitd that contains the change from that PR as well as older
    // toolchains that don't contain the change yet.
    XCTAssert(
      [
        "add stubs for conformance",
        "do you want to add protocol stubs?",
      ].contains(action.title)
    )
  }
}
