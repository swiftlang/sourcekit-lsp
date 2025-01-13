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
import SKOptions
import SKTestSupport
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
import XCTest

final class ExecuteCommandTests: XCTestCase {
  func testLocationSemanticRefactoring() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() {
        1️⃣"hello2️⃣"3️⃣
      }
      """,
      uri: uri
    )

    let args = SemanticRefactorCommand(
      title: "Localize String",
      actionString: "source.refactoring.kind.localize.string",
      positionRange: Range(positions["2️⃣"]),
      textDocument: TextDocumentIdentifier(uri)
    )

    let metadata = SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(uri))

    var command = args.asCommand()
    command.arguments?.append(metadata.encodeToLSPAny())

    let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

    let expectation = self.expectation(description: "Handle ApplyEditRequest")
    let applyEditTitle = ThreadSafeBox<String?>(initialValue: nil)
    let applyEditWorkspaceEdit = ThreadSafeBox<WorkspaceEdit?>(initialValue: nil)

    testClient.handleSingleRequest { (req: ApplyEditRequest) -> ApplyEditResponse in
      applyEditTitle.value = req.label
      applyEditWorkspaceEdit.value = req.edit
      expectation.fulfill()

      return ApplyEditResponse(applied: true, failureReason: nil)
    }

    let _ = try await testClient.send(request)

    try await fulfillmentOfOrThrow([expectation])

    let label = try XCTUnwrap(applyEditTitle.value)
    let edit = try XCTUnwrap(applyEditWorkspaceEdit.value)

    XCTAssertEqual(label, "Localize String")
    XCTAssertEqual(
      edit,
      WorkspaceEdit(changes: [
        uri: [
          TextEdit(
            range: Range(positions["1️⃣"]),
            newText: "NSLocalizedString("
          ),
          TextEdit(
            range: Range(positions["3️⃣"]),
            newText: ", comment: \"\")"
          ),
        ]
      ])
    )
  }

  func testRangeSemanticRefactoring() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() -> String {
        1️⃣var a = "hello"
        return a2️⃣
      }
      """,
      uri: uri
    )

    let args = SemanticRefactorCommand(
      title: "Extract Method",
      actionString: "source.refactoring.kind.extract.function",
      positionRange: positions["1️⃣"]..<positions["2️⃣"],
      textDocument: TextDocumentIdentifier(uri)
    )

    let metadata = SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(uri))

    var command = args.asCommand()
    command.arguments?.append(metadata.encodeToLSPAny())

    let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

    let expectation = self.expectation(description: "Handle ApplyEditRequest")
    let applyEditTitle = ThreadSafeBox<String?>(initialValue: nil)
    let applyEditWorkspaceEdit = ThreadSafeBox<WorkspaceEdit?>(initialValue: nil)

    testClient.handleSingleRequest { (req: ApplyEditRequest) -> ApplyEditResponse in
      applyEditTitle.value = req.label
      applyEditWorkspaceEdit.value = req.edit
      expectation.fulfill()

      return ApplyEditResponse(applied: true, failureReason: nil)
    }

    let _ = try await testClient.send(request)

    try await fulfillmentOfOrThrow([expectation])

    let label = try XCTUnwrap(applyEditTitle.value)
    let edit = try XCTUnwrap(applyEditWorkspaceEdit.value)

    XCTAssertEqual(label, "Extract Method")
    XCTAssertEqual(
      edit,
      WorkspaceEdit(changes: [
        uri: [
          TextEdit(
            range: Range(Position(line: 0, utf16index: 0)),
            newText:
              """
              fileprivate func extractedFunc() -> String {
              var a = "hello"
                return a
              }


              """
          ),
          TextEdit(
            range: positions["1️⃣"]..<positions["2️⃣"],
            newText: "return extractedFunc()"
          ),
        ]
      ])
    )
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
