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
import SKTestSupport
import SourceKitLSP
import XCTest

final class CodeActionTests: XCTestCase {

  typealias CodeActionCapabilities = TextDocumentClientCapabilities.CodeAction
  typealias CodeActionLiteralSupport = CodeActionCapabilities.CodeActionLiteralSupport
  typealias CodeActionKindCapabilities = CodeActionLiteralSupport.CodeActionKind

  private func clientCapabilitiesWithCodeActionSupport() -> ClientCapabilities {
    var documentCapabilities = TextDocumentClientCapabilities()
    var codeActionCapabilities = CodeActionCapabilities()
    let codeActionKinds = CodeActionKindCapabilities(valueSet: [.refactor, .quickFix])
    let codeActionLiteralSupport = CodeActionLiteralSupport(codeActionKind: codeActionKinds)
    codeActionCapabilities.codeActionLiteralSupport = codeActionLiteralSupport
    documentCapabilities.codeAction = codeActionCapabilities
    return ClientCapabilities(workspace: nil, textDocument: documentCapabilities)
  }

  private func refactorTibsWorkspace() throws -> SKTibsTestWorkspace? {
    let capabilities = clientCapabilitiesWithCodeActionSupport()
    return try staticSourceKitTibsWorkspace(name: "SemanticRefactor", clientCapabilities: capabilities)
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

  func testCodeActionResponseIgnoresSupportedKinds() {
    // The client guarantees that unsupported kinds will be handled, and in
    // practice some clients use `"codeActionKind":{"valueSet":[]}`, since
    // they support all kinds anyway. So to avoid filtering all actions, we
    // ignore the supported kinds.

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
    XCTAssertEqual(response, .codeActions([unspecifiedAction, refactorAction, quickfixAction]))

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
    XCTAssertEqual(response, .codeActions([unspecifiedAction, refactorAction, quickfixAction]))
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

  func testEmptyCodeActionResult() throws {
    guard let ws = try refactorTibsWorkspace() else { return }
    let loc = ws.testLoc("sr:foo")
    try ws.openDocument(loc.url, language: .swift)

    let textDocument = TextDocumentIdentifier(loc.url)
    let start = Position(line: 2, utf16index: 0)
    let request = CodeActionRequest(range: start..<start, context: .init(), textDocument: textDocument)
    let result = try ws.sk.sendSync(request)

    XCTAssertEqual(result, .codeActions([]))
  }

  func testSemanticRefactorLocalRenameResult() throws {
    guard let ws = try refactorTibsWorkspace() else { return }
    let loc = ws.testLoc("sr:local")
    try ws.openDocument(loc.url, language: .swift)

    let textDocument = TextDocumentIdentifier(loc.url)
    let request = CodeActionRequest(range: loc.position..<loc.position, context: .init(), textDocument: textDocument)
    let result = try ws.sk.sendSync(request)
    XCTAssertEqual(result, .codeActions([]))
  }

  func testSemanticRefactorLocationCodeActionResult() throws {
    guard let ws = try refactorTibsWorkspace() else { return }
    let loc = ws.testLoc("sr:string")
    try ws.openDocument(loc.url, language: .swift)

    let textDocument = TextDocumentIdentifier(loc.url)
    let request = CodeActionRequest(range: loc.position..<loc.position, context: .init(), textDocument: textDocument)
    let result = try ws.sk.sendSync(request)

    let expectedCommandArgs: LSPAny = ["actionString": "source.refactoring.kind.localize.string", "positionRange": ["start": ["character": 43, "line": 1], "end": ["character": 43, "line": 1]], "title": "Localize String", "textDocument": ["uri": .string(loc.url.absoluteString)]]

    let metadataArguments: LSPAny = ["sourcekitlsp_textDocument": ["uri": .string(loc.url.absoluteString)]]
    let expectedCommand = Command(title: "Localize String",
                                  command: "semantic.refactor.command",
                                  arguments: [expectedCommandArgs] + [metadataArguments])
    let expectedCodeAction = CodeAction(title: "Localize String",
                                        kind: .refactor,
                                        command: expectedCommand)

    XCTAssertEqual(result, .codeActions([expectedCodeAction]))
  }

  func testSemanticRefactorRangeCodeActionResult() throws {
    guard let ws = try refactorTibsWorkspace() else { return }
    let rangeStartLoc = ws.testLoc("sr:extractStart")
    let rangeEndLoc = ws.testLoc("sr:extractEnd")
    try ws.openDocument(rangeStartLoc.url, language: .swift)

    XCTAssertEqual(rangeStartLoc.url, rangeEndLoc.url)

    let textDocument = TextDocumentIdentifier(rangeStartLoc.url)
    let request = CodeActionRequest(range: rangeStartLoc.position..<rangeEndLoc.position, context: .init(), textDocument: textDocument)
    let result = try ws.sk.sendSync(request)

    let expectedCommandArgs: LSPAny = ["actionString": "source.refactoring.kind.extract.function", "positionRange": ["start": ["character": 21, "line": 1], "end": ["character": 27, "line": 2]], "title": "Extract Method", "textDocument": ["uri": .string(rangeStartLoc.url.absoluteString)]]
    let metadataArguments: LSPAny = ["sourcekitlsp_textDocument": ["uri": .string(rangeStartLoc.url.absoluteString)]]
    let expectedCommand = Command(title: "Extract Method",
                                  command: "semantic.refactor.command",
                                  arguments: [expectedCommandArgs] + [metadataArguments])
    let expectedCodeAction = CodeAction(title: "Extract Method",
                                        kind: .refactor,
                                        command: expectedCommand)

    XCTAssertEqual(result, .codeActions([expectedCodeAction]))
  }
}
