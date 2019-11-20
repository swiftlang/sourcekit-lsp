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

import LanguageServerProtocol
import SKTestSupport
import XCTest

public typealias URL = Foundation.URL

final class SKTests: XCTestCase {

    func testInitLocal() {
      let c = TestSourceKitServer()

      let sk = c.client

      let initResult = try! sk.sendSync(InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
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
        rootURI: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))

      XCTAssertEqual(initResult.capabilities.textDocumentSync?.openClose, true)
      XCTAssertNotNil(initResult.capabilities.completionProvider)
    }

  func testIndexSwiftModules() throws {
    guard let ws = try staticSourceKitTibsWorkspace(name: "SwiftModules") else { return }
    try ws.buildAndIndex()

    let locDef = ws.testLoc("aaa:def")
    let locRef = ws.testLoc("aaa:call:c")

    try ws.openDocument(locDef.url, language: .swift)
    try ws.openDocument(locRef.url, language: .swift)

    // MARK: Jump to definition

    let jump = try ws.sk.sendSync(DefinitionRequest(
      textDocument: locRef.docIdentifier,
      position: locRef.position))

    XCTAssertEqual(jump.count, 1)
    XCTAssertEqual(jump.first?.uri, DocumentURI(locDef.url))
    XCTAssertEqual(jump.first?.range.lowerBound, locDef.position)

    // MARK: Find references

    let refs = try ws.sk.sendSync(ReferencesRequest(
      textDocument: locDef.docIdentifier,
      position: locDef.position))

    XCTAssertEqual(Set(refs), [
      Location(locDef),
      Location(locRef),
      Location(ws.testLoc("aaa:call")),
    ])
  }

  func testIndexShutdown() throws {

    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("sk-test-data/\(testDirectoryName)", isDirectory: true)

    func listdir(_ url: URL) throws -> [URL] {
      try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    func checkRunningIndex(build: Bool) throws -> URL? {
      guard let ws = try staticSourceKitTibsWorkspace(
        name: "SwiftModules", tmpDir: tmpDir, removeTmpDir: false)
      else {
        return nil
      }

      if build {
        try ws.buildAndIndex()
      }

      let locDef = ws.testLoc("aaa:def")
      let locRef = ws.testLoc("aaa:call:c")
      try ws.openDocument(locRef.url, language: .swift)
      let jump = try ws.sk.sendSync(DefinitionRequest(
        textDocument: locRef.docIdentifier,
        position: locRef.position))
      XCTAssertEqual(jump.count, 1)
      XCTAssertEqual(jump.first?.url, locDef.url)
      XCTAssertEqual(jump.first?.range.lowerBound, locDef.position)

      let tmpContents = try listdir(tmpDir)
      guard let versionedPath = tmpContents.filter({ $0.lastPathComponent.starts(with: "v") }).spm_only else {
        XCTFail("expected one version path 'v[0-9]*', found \(tmpContents)")
        return nil
      }

      let versionContentsBefore = try listdir(versionedPath)
      XCTAssertEqual(versionContentsBefore.count, 1)
      XCTAssert(versionContentsBefore.first?.lastPathComponent.starts(with: "p") ?? false)

      _ = try ws.sk.sendSync(Shutdown())
      return versionedPath
    }

    guard let versionedPath = try checkRunningIndex(build: true) else { return }
    
    let versionContentsAfter = try listdir(versionedPath)
    XCTAssertEqual(versionContentsAfter.count, 1)
    XCTAssertEqual(versionContentsAfter.first?.lastPathComponent, "saved")

    _ = try checkRunningIndex(build: true)

    try FileManager.default.removeItem(atPath: tmpDir.path)
  }

  func testCodeCompleteSwiftTibs() throws {
    guard let ws = try staticSourceKitTibsWorkspace(name: "CodeCompleteSingleModule") else { return }
    let loc = ws.testLoc("cc:A")
    try ws.openDocument(loc.url, language: .swift)

    let results = try ws.sk.sendSync(
      CompletionRequest(textDocument: loc.docIdentifier, position: loc.position))

    XCTAssertEqual(results, CompletionList(isIncomplete: false, items: [
      CompletionItem(
        label: "method(a: Int)",
        detail: "Void",
        sortText: nil,
        filterText: "method(a:)",
        textEdit: nil,
        insertText: "method(a: )",
        insertTextFormat: .plain,
        kind: .method,
        deprecated: nil),
      CompletionItem(
        label: "self",
        detail: "A",
        sortText: nil,
        filterText: "self",
        textEdit: nil,
        insertText: "self",
        insertTextFormat: .plain,
        kind: .keyword,
        deprecated: nil),
    ]))
  }
}
