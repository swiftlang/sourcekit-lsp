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

import LanguageServerProtocol
import SKTestSupport
import XCTest

class AddMissingImportsTests: SourceKitLSPTestCase {
  private var clientCapabilitiesWithCodeActionSupport: ClientCapabilities {
    var documentCapabilities = TextDocumentClientCapabilities()
    var codeActionCapabilities = TextDocumentClientCapabilities.CodeAction()
    let codeActionKinds = TextDocumentClientCapabilities.CodeAction.CodeActionLiteralSupport.CodeActionKindValueSet(
      valueSet: [.refactor, .quickFix])
    let codeActionLiteralSupport = TextDocumentClientCapabilities.CodeAction.CodeActionLiteralSupport(
      codeActionKind: codeActionKinds
    )
    codeActionCapabilities.codeActionLiteralSupport = codeActionLiteralSupport
    documentCapabilities.codeAction = codeActionCapabilities
    return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
  }

  func testAddMissingImport() async throws {
    // This test relies on the index, so it needs to run where we can build and index.
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Lib/Lib.swift": """
        public struct LibStruct {}
        """,
        "Exec/main.swift": """
        1️⃣func test() {
          _ = 2️⃣LibStruct()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          products: [
            .library(name: "Lib", targets: ["Lib"])
          ],
          targets: [
            .target(name: "Lib"),
            .executableTarget(name: "Exec", dependencies: ["Lib"])
          ]
        )
        """,
      capabilities: clientCapabilitiesWithCodeActionSupport,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("main.swift")

    // Get the diagnostics
    var diagnostic: Diagnostic?
    let diags = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    diagnostic = diags.fullReport?.items.first { $0.message.contains("LibStruct") }
    XCTAssert(diagnostic != nil)

    let foundDiagnostic = try XCTUnwrap(diagnostic)

    let request = CodeActionRequest(
      range: Range(positions["2️⃣"]),
      context: CodeActionContext(diagnostics: [foundDiagnostic], only: [.quickFix]),
      textDocument: TextDocumentIdentifier(uri)
    )

    let response = try await project.testClient.send(request)
    guard case .codeActions(let actions) = response else {
      XCTFail("Expected code actions response")
      return
    }

    let codeAction = try XCTUnwrap(actions.first { $0.title == "Import Lib" })
    let command = try XCTUnwrap(codeAction.command)

    // Validate the edit inline when executing the command
    project.testClient.handleSingleRequest { (request: ApplyEditRequest) -> ApplyEditResponse in
      XCTAssertEqual(
        request.edit.changes,
        [
          uri: [
            TextEdit(range: Range(positions["1️⃣"]), newText: "import Lib\n")
          ]
        ]
      )
      return ApplyEditResponse(applied: true, failureReason: nil)
    }

    _ = try await project.testClient.send(
      ExecuteCommandRequest(command: command.command, arguments: command.arguments)
    )
  }
}
