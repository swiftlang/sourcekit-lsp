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
        func test() {
          let a = 1️⃣LibStruct()
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
      enableBackgroundIndexing: false
    )

    let (uri, positions) = try project.openDocument("main.swift")

    // We build only `Lib` so that we get the index for it, but don't fail because `Exec` doesn't build.
    try await SwiftPMTestProject.build(
      at: project.scratchDirectory,
      buildTests: false,
      extraArguments: ["--target", "Lib"]
    )

    try await project.testClient.send(SynchronizeRequest(index: true))

    // Wait for the diagnostic to appear. The compiler should complain about missing LibStruct.
    var foundDiagnostic: Diagnostic?
    // Try for up to 30 seconds
    for _ in 0..<30 {
      let diags = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      if let d = diags.fullReport?.items.first(where: { $0.message.contains("Cannot find 'LibStruct' in scope") }) {
        foundDiagnostic = d
        break
      }
      try await Task.sleep(for: .seconds(1))
    }

    guard let diagnostic = foundDiagnostic else {
      XCTFail("Did not find expected diagnostic check 'Cannot find LibStruct in scope' after polling")
      return
    }

    let request = CodeActionRequest(
      range: Range(positions["1️⃣"]),
      context: CodeActionContext(diagnostics: [diagnostic], only: [.quickFix]),
      textDocument: TextDocumentIdentifier(uri)
    )

    var codeAction: CodeAction?
    for _ in 0..<5 {
      let response = try await project.testClient.send(request)
      if case .codeActions(let actions) = response {
        if let action = actions.first(where: { $0.title == "Import Lib" }) {
          codeAction = action
          break
        }
      }
      try await Task.sleep(for: .seconds(1))
    }

    XCTAssertNotNil(codeAction)

    if let codeAction {
      guard let changes = codeAction.edit?.changes?[uri] else {
        XCTFail("No edit changes found")
        return
      }
      XCTAssertTrue(changes.contains { $0.newText.contains("import Lib") })
    }
  }
}
