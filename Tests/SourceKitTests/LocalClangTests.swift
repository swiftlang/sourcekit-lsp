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
import SKCore
import SKTestSupport
import XCTest

final class LocalClangTests: XCTestCase {

  /// Whether to fail tests if clangd cannot be found.
  static let requireClangd: Bool = false // Note: Swift CI doesn't build clangd on all jobs

  /// Whether clangd exists in the toolchain.
  var haveClangd: Bool = false

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  override func setUp() {
    haveClangd = ToolchainRegistry.shared.toolchains.contains { $0.clangd != nil }
    if LocalClangTests.requireClangd && !haveClangd {
      XCTFail("cannot find clangd in toolchain")
    }

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

  override func tearDown() {
    sk = nil
    connection = nil
  }

  // MARK: Tests

  func testSymbolInfo() {
    guard haveClangd else { return }
    let url = URL(fileURLWithPath: "/a.cpp")

    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .cpp,
      version: 1,
      text: """
      struct S {
        void foo() {
          int local = 1;
        }
      };
      """)))

    do {
      let resp = try! sk.sendSync(SymbolInfoRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 0, utf16index: 7)))

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "S")
        XCTAssertNil(sym.containerName)
        XCTAssertEqual(sym.usr, "c:@S@S")
      }
    }

    do {
      let resp = try! sk.sendSync(SymbolInfoRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 1, utf16index: 7)))

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "foo")
        XCTAssertEqual(sym.containerName, "S::")
        XCTAssertEqual(sym.usr, "c:@S@S@F@foo#")
      }
    }

    do {
      let resp = try! sk.sendSync(SymbolInfoRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 2, utf16index: 8)))

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "local")
        XCTAssertEqual(sym.containerName, "S::foo")
        XCTAssertEqual(sym.usr, "c:a.cpp@30@S@S@F@foo#@local")
      }
    }

    do {
      let resp = try! sk.sendSync(SymbolInfoRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 3, utf16index: 0)))

      XCTAssertEqual(resp.count, 0)
    }
  }

  func testFoldingRange() {
    guard haveClangd else { return }
    let url = URL(fileURLWithPath: "/a.cpp")

    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .cpp,
      version: 1,
      text: """
      struct S {
        void foo() {
          int local = 1;
        }
      };
      """)))

    let resp = try! sk.sendSync(FoldingRangeRequest(textDocument: TextDocumentIdentifier(url)))
    XCTAssertNil(resp)
  }

  func testClangStdHeaderCanary() throws {
    guard let ws = try staticSourceKitTibsWorkspace(name: "ClangStdHeaderCanary") else { return }
    if ToolchainRegistry.shared.default?.clangd == nil { return }

    let loc = ws.testLoc("unused_b")

    let expectation = XCTestExpectation(description: "diagnostics")

    ws.sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      // Don't use exact equality because of differences in recent clang.
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(note.params.diagnostics.first?.range,
        Position(loc) ..< Position(ws.testLoc("unused_b:end")))
      XCTAssertEqual(note.params.diagnostics.first?.severity, .warning)
      XCTAssertEqual(note.params.diagnostics.first?.message, "Unused variable 'b'")
      expectation.fulfill()
    }

    try ws.openDocument(loc.url, language: .cpp)

    let result = XCTWaiter.wait(for: [expectation], timeout: 15)
    if result != .completed {
      fatalError("error \(result) waiting for diagnostics notification")
    }
  }

  func testClangModules() {
    guard let ws = try! staticSourceKitTibsWorkspace(name: "ClangModules") else { return }
    if ToolchainRegistry.shared.default?.clangd == nil { return }

    let loc = ws.testLoc("main_file")

    let expectation = self.expectation(description: "diagnostics")

    ws.sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 0)
      expectation.fulfill()
    }

    try! ws.openDocument(loc.url, language: .objective_c)

    waitForExpectations(timeout: 15)
  }
}
