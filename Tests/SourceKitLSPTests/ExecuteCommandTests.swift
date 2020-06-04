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
import LSPTestSupport
import SKTestSupport
import SourceKitLSP
import XCTest

final class ExecuteCommandTests: XCTestCase {

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  override func tearDown() {
    sk = nil
    connection = nil
  }

  override func setUp() {
    connection = TestSourceKitServer()
    sk = connection.client
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
      trace: .off,
      workspaceFolders: nil))
  }

  func testLocationSemanticRefactoring() throws {
    guard let ws = try staticSourceKitTibsWorkspace(name: "SemanticRefactor") else { return }
    let loc = ws.testLoc("sr:string")
    try ws.openDocument(loc.url, language: .swift)

    let textDocument = TextDocumentIdentifier(loc.url)

    let args = SemanticRefactorCommand(title: "Localize String",
                                       actionString: "source.refactoring.kind.localize.string",
                                       positionRange: loc.position..<loc.position,
                                       textDocument: textDocument)

    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)

    var command = try args.asCommand()
    command.arguments?.append(metadata.encodeToLSPAny())

    let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

    ws.testServer.client.handleNextRequest { (req: Request<ApplyEditRequest>) in
      req.reply(ApplyEditResponse(applied: true, failureReason: nil))
    }

    let result = try ws.sk.sendSync(request)

    guard case .dictionary(let resultDict) = result else {
      XCTFail("Result is not a dictionary.")
      return
    }

    XCTAssertEqual(WorkspaceEdit(fromLSPDictionary: resultDict), WorkspaceEdit(changes: [
      DocumentURI(loc.url): [
        TextEdit(range: Position(line: 1, utf16index: 29)..<Position(line: 1, utf16index: 29),
                 newText: "NSLocalizedString("),
        TextEdit(range: Position(line: 1, utf16index: 44)..<Position(line: 1, utf16index: 44),
                 newText: ", comment: \"\")")
      ]
    ]))
  }

  func testRangeSemanticRefactoring() throws {
    guard let ws = try staticSourceKitTibsWorkspace(name: "SemanticRefactor") else { return }
    let loc = ws.testLoc("sr:foo")
    try ws.openDocument(loc.url, language: .swift)

    let textDocument = TextDocumentIdentifier(loc.url)

    let startPosition = Position(line: 1, utf16index: 2)
    let endPosition = Position(line: 2, utf16index: 10)

    let args = SemanticRefactorCommand(title: "Extract Method",
                                       actionString: "source.refactoring.kind.extract.function",
                                       positionRange: startPosition..<endPosition,
                                       textDocument: textDocument)

    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)

    var command = try args.asCommand()
    command.arguments?.append(metadata.encodeToLSPAny())

    let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

    ws.testServer.client.handleNextRequest { (req: Request<ApplyEditRequest>) in
      req.reply(ApplyEditResponse(applied: true, failureReason: nil))
    }

    let result = try ws.sk.sendSync(request)

    guard case .dictionary(let resultDict) = result else {
      XCTFail("Result is not a dictionary.")
      return
    }

    XCTAssertEqual(WorkspaceEdit(fromLSPDictionary: resultDict), WorkspaceEdit(changes: [
      DocumentURI(loc.url): [
        TextEdit(range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
                 newText: "fileprivate func extractedFunc() -> String {\n/*sr:extractStart*/var a = \"/*sr:string*/\"\n  return a\n}\n\n"),
        TextEdit(range: Position(line: 1, utf16index: 2)..<Position(line: 2, utf16index: 10),
                 newText: "return extractedFunc()")
      ]
    ]))
  }

  func testLSPCommandMetadataRetrieval() {
    var req = ExecuteCommandRequest(command: "", arguments: nil)
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, ""]
    XCTAssertNil(req.metadata)
    let url = URL(fileURLWithPath: "/a.swift")
    let textDocument = TextDocumentIdentifier(url)
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    req.arguments = [metadata.encodeToLSPAny(), 1, 2, ""]
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, "", [metadata.encodeToLSPAny()]]
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, "", metadata.encodeToLSPAny()]
    XCTAssertEqual(req.metadata, metadata)
    req.arguments = [metadata.encodeToLSPAny()]
    XCTAssertEqual(req.metadata, metadata)
  }

  func testLSPCommandMetadataRemoval() {
    var req = ExecuteCommandRequest(command: "", arguments: nil)
    XCTAssertNil(req.argumentsWithoutSourceKitMetadata)
    req.arguments = [1, 2, ""]
    XCTAssertEqual(req.arguments, req.argumentsWithoutSourceKitMetadata)
    let url = URL(fileURLWithPath: "/a.swift")
    let textDocument = TextDocumentIdentifier(url)
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    req.arguments = [metadata.encodeToLSPAny(), 1, 2, ""]
    XCTAssertEqual(req.arguments, req.argumentsWithoutSourceKitMetadata)
    req.arguments = [1, 2, "", [metadata.encodeToLSPAny()]]
    XCTAssertEqual(req.arguments, req.argumentsWithoutSourceKitMetadata)
    req.arguments = [1, 2, "", metadata.encodeToLSPAny()]
    XCTAssertEqual([1, 2, ""], req.argumentsWithoutSourceKitMetadata)
  }
}
