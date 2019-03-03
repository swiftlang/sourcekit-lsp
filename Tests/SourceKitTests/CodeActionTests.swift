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

final class CodeActionTests: XCTestCase {

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  var workspace: Workspace! = nil

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

  override func tearDown() {
    workspace = nil
    sk = nil
    connection = nil
  }

  func testCommandEncoding() {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true

    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: "")))

    let json = """
    {
      "command" : "sourcekit.lsp.semantic.refactoring.command",
      "arguments" : [{"uri" : "file:///a.swift"}, {
        "title" : "Localize String",
        "actionString" : "source.refactoring.kind.localize.string",
        "line" : 1,
        "column" : 10,
        "length" : 5
      }]
    }
    """

    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let decodedCommand = try! decoder.decode(Command.self, from: data)

    let textDocument = TextDocumentIdentifier(url)

    let args = SemanticRefactorCommandArgs(title: "Localize String",
                                           actionString: "source.refactoring.kind.localize.string",
                                           line: 1,
                                           column: 10,
                                           length: 5)

    let command = Command.semanticRefactor(textDocument, args)
    XCTAssertEqual(decodedCommand, command)

    let enc = try! JSONEncoder().encode(command)
    let dec = try! JSONDecoder().decode(Command.self, from: enc)

    XCTAssertEqual(dec, command)
  }
}
