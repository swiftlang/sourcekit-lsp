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
import SourceKit

final class CodeActionTests: XCTestCase {

  typealias CodeActionCapabilities = TextDocumentClientCapabilities.CodeAction
  typealias CodeActionLiteralSupport = CodeActionCapabilities.CodeActionLiteralSupport
  typealias CodeActionKindCapabilities = CodeActionLiteralSupport.CodeActionKind

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
    var documentCapabilities = TextDocumentClientCapabilities()
    var codeActionCapabilities = CodeActionCapabilities()
    let codeActionKinds = CodeActionKindCapabilities(valueSet: [.refactor, .quickFix])
    let codeActionLiteralSupport = CodeActionLiteralSupport(codeActionKind: codeActionKinds)
    codeActionCapabilities.codeActionLiteralSupport = codeActionLiteralSupport
    documentCapabilities.codeAction = codeActionCapabilities
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURL: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))

    workspace = connection.server!.workspace!
  }

  func testCodeActionResponseLegacySupport() {
    let command = Command(title: "Title", command: "Command", arguments: [1, "text", 2.2, nil])
    let codeAction = CodeAction(title: "1")
    let codeAction2 = CodeAction(title: "2", command: command)

    var capabilities: TextDocumentClientCapabilities.CodeAction
    var capabilityJson: String
    var data: Data
    var response: CodeActionRequestResponse
    capabilityJson =
    """
     {
       "dynamicRegistration": true,
       "codeActionLiteralSupport" : {
         "codeActionKind": {
           "valueSet": []
         }
       }
     }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)
    response = .init(codeActions: [codeAction, codeAction2], clientCapabilities: capabilities)
    let actions = try! JSONDecoder().decode([CodeAction].self, from: JSONEncoder().encode(response))
    XCTAssertEqual(actions, [codeAction, codeAction2])

    capabilityJson =
    """
    {
      "dynamicRegistration": true
    }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)
    response = .init(codeActions: [codeAction, codeAction2], clientCapabilities: capabilities)
    let commands = try! JSONDecoder().decode([Command].self, from: JSONEncoder().encode(response))
    XCTAssertEqual(commands, [command])
  }

  func testCodeActionResponseRespectsSupportedKinds() {
    let unspecifiedAction = CodeAction(title: "Unspecified")
    let refactorAction = CodeAction(title: "Refactor", kind: .refactor)
    let quickfixAction = CodeAction(title: "Quickfix", kind: .quickFix)
    let actions = [unspecifiedAction, refactorAction, quickfixAction]

    var capabilities: TextDocumentClientCapabilities.CodeAction
    var capabilityJson: String
    var data: Data
    var response: CodeActionRequestResponse
    capabilityJson =
    """
    {
      "dynamicRegistration": true,
      "codeActionLiteralSupport" : {
        "codeActionKind": {
          "valueSet": ["refactor"]
        }
      }
    }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)

    response = .init(codeActions: actions, clientCapabilities: capabilities)
    XCTAssertEqual(response, .codeActions([unspecifiedAction, refactorAction]))

    capabilityJson =
    """
    {
      "dynamicRegistration": true,
      "codeActionLiteralSupport" : {
        "codeActionKind": {
          "valueSet": []
        }
      }
    }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)

    response = .init(codeActions: actions, clientCapabilities: capabilities)
    XCTAssertEqual(response, .codeActions([unspecifiedAction]))
  }

  func testCodeActionResponseCommandMetadataInjection() {
    let url = URL(fileURLWithPath: "/a.swift")
    let textDocument = TextDocumentIdentifier(url)
    let expectedMetadata: LSPAny = {
      let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
      let data = try! JSONEncoder().encode(metadata)
      return try! JSONDecoder().decode(LSPAny.self, from: data)
    }()
    XCTAssertEqual(expectedMetadata, .dictionary(["sourcekitlsp_textDocument": ["uri": "file:///a.swift"]]))
    let command = Command(title: "Title", command: "Command", arguments: [1, "text", 2.2, nil])
    let codeAction = CodeAction(title: "1")
    let codeAction2 = CodeAction(title: "2", command: command)
    let request = CodeActionRequest(range: Position(line: 0, utf16index: 0)..<Position(line: 1, utf16index: 1),
                                    context: .init(diagnostics: [], only: nil),
                                    textDocument: textDocument)
    var response = request.injectMetadata(toResponse: .commands([command]))
    XCTAssertEqual(response,
          .commands([
            Command(title: command.title,
                    command: command.command,
                    arguments: command.arguments! + [expectedMetadata])
          ])
    )
    response = request.injectMetadata(toResponse: .codeActions([codeAction, codeAction2]))
    XCTAssertEqual(response,
          .codeActions([codeAction,
            CodeAction(title: codeAction2.title,
                       command: Command(title: command.title,
                                        command: command.command,
                                        arguments: command.arguments! + [expectedMetadata]))
          ])
    )
    response = request.injectMetadata(toResponse: nil)
    XCTAssertNil(response)
  }

  func testCommandEncoding() {
    let dictionary: LSPAny = ["1": [nil, 2], "2": "text", "3": ["4": [1, 2]]]
    let array: LSPAny = [1, [2,"string"], dictionary]
    let arguments: LSPAny = [1, 2.2, "text", nil, array, dictionary]
    let command = Command(title: "Command", command: "command.id", arguments: [arguments, arguments])
    let decoded = try! JSONDecoder().decode(Command.self, from: JSONEncoder().encode(command))
    XCTAssertEqual(decoded, command)
  }

  func testEmptyCodeActionResult() {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true

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
    let start = Position(line: 2, utf16index: 0)
    let request = CodeActionRequest(range: start..<start, context: .init(), textDocument: textDocument)
    let result = try! sk.sendSync(request)
    XCTAssertEqual(result, .codeActions([]))
  }

  func testSemanticRefactorCodeActionResult() {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true

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
    let start = Position(line: 1, utf16index: 11)
    let request = CodeActionRequest(range: start..<start, context: .init(), textDocument: textDocument)
    let result = try! sk.sendSync(request)

    let expectedCommandArgs: LSPAny = ["actionString": "source.refactoring.kind.localize.string", "positionRange": ["start": ["character": 11, "line": 1], "end": ["character": 11, "line": 1]], "title": "Localize String", "textDocument": ["uri": "file:///a.swift"]]
    let metadataArguments: LSPAny = ["sourcekitlsp_textDocument": ["uri": "file:///a.swift"]]
    let expectedCommand = Command(title: "Localize String",
                                  command: "semantic.refactor.command",
                                  arguments: [expectedCommandArgs] + [metadataArguments])
    let expectedCodeAction = CodeAction(title: "Localize String",
                                        kind: .refactor,
                                        command: expectedCommand)

    XCTAssertEqual(result, .codeActions([expectedCodeAction]))
  }
}
