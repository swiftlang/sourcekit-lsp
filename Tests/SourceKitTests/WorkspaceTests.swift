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

@testable import SKCore
@testable import SourceKit
import LanguageServerProtocol
import Basic
import SKSupport
import SKTestSupport
import XCTest

final class WorkspaceTests: XCTestCase {

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  var fs: FileSystem!

  override func setUp() {
    fs = InMemoryFileSystem()
    connection = TestSourceKitServer(fileSystem: fs)
    sk = connection.client
  }

  func testWorkspaceFolders() {
#if os(macOS)
    let fs = InMemoryFileSystem()
    try! fs.createDirectory(AbsolutePath("/a"))
    try! fs.createDirectory(AbsolutePath("/b"))

    let folderA = WorkspaceFolder(url: URL(string: "/a")!)
    let fileAURL = URL(string: "/a/testa.swift")!
    try! fs.writeFileContents(AbsolutePath(fileAURL.path), bytes: """
      func
      """)

    let folderB = WorkspaceFolder(url: URL(string: "/b")!)
    let fileBURL = URL(string: "/b/testb.swift")!
    try! fs.writeFileContents(AbsolutePath(fileBURL.path), bytes: """
      class
      """)

    var workspaceCapabilities = WorkspaceClientCapabilities()
    workspaceCapabilities.workspaceFolders = true

    let initResult = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURL: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: workspaceCapabilities, textDocument: nil),
      trace: .off,
      workspaceFolders: [folderA, folderB]))

    XCTAssertEqual(connection.server?.workspaces.count, 2)
    XCTAssertEqual(initResult.capabilities.workspace?.workspaceFolders?.supported, true)

    try! sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: fileAURL,
      language: .swift,
      version: 1,
      text: fs.readFileContents(AbsolutePath(fileAURL.path)).asReadableString))) { (note: Notification<PublishDiagnostics>) in
        log("Received diagnostics for open - syntactic")
        XCTAssertEqual(note.params.diagnostics.count, 1)
        XCTAssertEqual("func", self.connection.server?.workspaces[0].documentManager.latestSnapshot(fileAURL)!.text)
    }

    try! sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: fileBURL,
      language: .swift,
      version: 1,
      text: fs.readFileContents(AbsolutePath(fileBURL.path)).asReadableString))) { (note: Notification<PublishDiagnostics>) in
        log("Received diagnostics for open - syntactic")
        XCTAssertEqual(note.params.diagnostics.count, 1)
        XCTAssertEqual("class", self.connection.server?.workspaces[1].documentManager.latestSnapshot(fileBURL)!.text)
    }
#endif
  }

  func testAddingWorkspaceFolders() {
#if os(macOS)
    let folderA = WorkspaceFolder(url: URL(string: "/a")!)
    let folderB = WorkspaceFolder(url: URL(string: "/b")!)

    var workspaceCapabilities = WorkspaceClientCapabilities()
    workspaceCapabilities.workspaceFolders = true

    let _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURL: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: workspaceCapabilities, textDocument: nil),
      trace: .off,
      workspaceFolders: [folderA]))

    XCTAssertEqual(connection.server?.workspaces.count, 1)

    sk.send(DidChangeWorkspaceFolders(event:
      WorkspaceFoldersChangeEvent(added: [folderB])
    ))

    XCTAssertTrue(wait(for: { $0?.workspaces.count == 2 }, object: connection.server))

    sk.send(DidChangeWorkspaceFolders(event:
      WorkspaceFoldersChangeEvent(removed: [folderA])
    ))

    XCTAssertTrue(wait(for: { $0?.workspaces.count == 1 }, object: connection.server))
#endif
  }

  override func tearDown() {
    sk = nil
    connection = nil
    fs = nil
  }
}
