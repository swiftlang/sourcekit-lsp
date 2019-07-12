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
  func testLSPCommandMetadataRetrieval() {
    var req = ExecuteCommandRequest(command: "", arguments: nil)
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, ""]
    XCTAssertNil(req.metadata)
    let url = URL(fileURLWithPath: "/a.swift")
    let textDocument = TextDocumentIdentifier(url)
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    req.arguments = [metadata.asCommandArgument(), 1, 2, ""]
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, "", [metadata.asCommandArgument()]]
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, "", metadata.asCommandArgument()]
    XCTAssertEqual(req.metadata, metadata)
    req.arguments = [metadata.asCommandArgument()]
    XCTAssertEqual(req.metadata, metadata)
  }

  func testLSPCommandMetadataRemoval() {
    var req = ExecuteCommandRequest(command: "", arguments: nil)
    XCTAssertNil(req.argumentsWithoutLSPMetadata)
    req.arguments = [1, 2, ""]
    XCTAssertEqual(req.arguments, req.argumentsWithoutLSPMetadata)
    let url = URL(fileURLWithPath: "/a.swift")
    let textDocument = TextDocumentIdentifier(url)
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    req.arguments = [metadata.asCommandArgument(), 1, 2, ""]
    XCTAssertEqual(req.arguments, req.argumentsWithoutLSPMetadata)
    req.arguments = [1, 2, "", [metadata.asCommandArgument()]]
    XCTAssertEqual(req.arguments, req.argumentsWithoutLSPMetadata)
    req.arguments = [1, 2, "", metadata.asCommandArgument()]
    XCTAssertEqual([1, 2, ""], req.argumentsWithoutLSPMetadata)
  }
}
