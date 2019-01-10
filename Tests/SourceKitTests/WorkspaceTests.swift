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
    let fs = InMemoryFileSystem()
    try! fs.createDirectory(AbsolutePath("/a"))
    try! fs.createDirectory(AbsolutePath("/b"))

    let folderA = WorkspaceFolder(url: URL(string: "/a")!)
    let folderB = WorkspaceFolder(url: URL(string: "/b")!)

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
  }

  override func tearDown() {
    sk = nil
    connection = nil
    fs = nil
  }
}
