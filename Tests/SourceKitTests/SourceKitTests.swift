//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import SourceKit
import LanguageServerProtocol
import SKTestSupport
import XCTest

final class SKTests: XCTestCase {

    func testInitLocal() {
      let c = TestSourceKitServer()

      let sk = c.client

      let initResult = try! sk.sendSync(InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURL: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))

      XCTAssertEqual(initResult.capabilities.textDocumentSync?.openClose, true)
      XCTAssertNotNil(initResult.capabilities.completionProvider)
    }

    func testInitJSON() {
      let c = TestSourceKitServer(connectionKind: .jsonrpc)

      let sk = c.client

      let initResult = try! sk.sendSync(InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURL: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))

      XCTAssertEqual(initResult.capabilities.textDocumentSync?.openClose, true)
      XCTAssertNotNil(initResult.capabilities.completionProvider)
    }
}
