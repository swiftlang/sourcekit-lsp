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

  func testSemanticRefactoring() {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true
    sk.allowUnexpectedRequest = true

    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: """
    func foo() -> String {
      var a = "abc"
      return a
    }
    """)))

    let textDocument = TextDocumentIdentifier(url)

    let args = SemanticRefactorCommand(title: "Localize String",
                                       actionString: "source.refactoring.kind.localize.string",
                                       line: 1,
                                       column: 10,
                                       length: 5,
                                       textDocument: textDocument)

    let command = try! args.asCommand()
    let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

    let result = try! sk.sendSync(request)
    XCTAssertEqual(result, WorkspaceEdit(changes: [
      url: [TextEdit(range: Position(line: 1, utf16index: 10)..<Position(line: 1, utf16index: 10),
                     newText: "NSLocalizedString("),
            TextEdit(range: Position(line: 1, utf16index: 15)..<Position(line: 1, utf16index: 15),
                     newText: ", comment: \"\")")]
    ]))
  }
}
