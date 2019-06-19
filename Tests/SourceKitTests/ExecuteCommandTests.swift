//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKCore
import SKSupport
import SKTestSupport
import XCTest

@testable import SourceKit

final class ExecuteCommandTests: XCTestCase {

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  var workspace: Workspace! = nil

  override func tearDown() {
    workspace = nil
    sk = nil
    connection = nil
  }

  override func setUp() {
    connection = TestSourceKitServer()
    sk = connection.client
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURL: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
      trace: .off,
      workspaceFolders: nil))

    workspace = connection.server!.workspace!
  }

  func testCommandIsRoutedToTheCorrectServer() {

// FIXME: See comment on sendNoteSync.
#if os(macOS)

    let haveClangd = ToolchainRegistry.shared.toolchains.contains { $0.clangd != nil }
    if !haveClangd {
      XCTFail("Cannot find clangd in toolchain")
    }

    var req = ExecuteCommandRequest(command: "swift.lsp.command", arguments: nil)
    var service = connection.server?.serviceFor(executeCommandRequest: req, workspace: workspace)
    XCTAssertNil(service)

    sk.allowUnexpectedNotification = true
    let swiftUrl = URL(fileURLWithPath: "/a.swift")
    sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: swiftUrl,
      language: .swift,
      version: 12,
      text: """
    var foo = ""
    """)), { (note: Notification<PublishDiagnostics>) in
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual("var foo = \"\"", self.workspace.documentManager.latestSnapshot(swiftUrl)!.text)
    })
    let cUrl = URL(fileURLWithPath: "/b.cpp")
    sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: cUrl,
      language: .cpp,
      version: 1,
      text: """
    int foo = 1;
    """)), { (note: Notification<PublishDiagnostics>) in
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual("int foo = 1;", self.workspace.documentManager.latestSnapshot(cUrl)!.text)
    })

    XCTAssertEqual(workspace.documentService.count, 2)
    service = connection.server?.serviceFor(executeCommandRequest: req, workspace: workspace)
    XCTAssertTrue((service as? LocalConnection)?.handler is SwiftLanguageServer)
    req = ExecuteCommandRequest(command: "generic.lsp.command", arguments: nil)
    service = connection.server?.serviceFor(executeCommandRequest: req, workspace: workspace)
    XCTAssertTrue((service as? LocalConnection)?.handler is ClangLanguageServerShim)

#endif
  }
}
