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

import SourceKit
import TSCBasic
import LanguageServerProtocol
import SKCore
import SKSupport
import SKTestSupport
import XCTest

// Workaround ambiguity with Foundation.
typealias LSPNotification = LanguageServerProtocol.Notification

/// Build system to be used for testing BuildSystem and BuildSystemDelegate functionality with SourceKitServer
/// and other components.
final class TestBuildSystem: BuildSystem {
  var indexStorePath: AbsolutePath? = nil
  var indexDatabasePath: AbsolutePath? = nil

  weak var delegate: BuildSystemDelegate?

  /// Build settings by file.
  var buildSettingsByFile: [URL: FileBuildSettings] = [:]

  /// Toolchains by file.
  var toolchainsByFile: [URL: Toolchain] = [:]

  /// Files currently being watched by our delegate.
  var watchedFiles: Set<URL> = []

  func settings(for url: URL, _ language: Language) -> FileBuildSettings? {
    return buildSettingsByFile[url]
  }

  func toolchain(for url: URL, _ language: Language) -> Toolchain? {
    return toolchainsByFile[url]
  }

  func registerForChangeNotifications(for url: URL) {
    watchedFiles.insert(url)
  }

  func unregisterForChangeNotifications(for url: URL) {
    watchedFiles.remove(url)
  }
}

final class BuildSystemTests: XCTestCase {

  /// Connection and lifetime management for the service.
  var testServer: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  var workspace: Workspace! = nil

  /// The build system that we use to verify SourceKitServer behavior.
  var buildSystem: TestBuildSystem! = nil

  /// Whether clangd exists in the toolchain.
  var haveClangd: Bool = false

  override func setUp() {
    haveClangd = ToolchainRegistry.shared.toolchains.contains { $0.clangd != nil }
    testServer = TestSourceKitServer()
    buildSystem = TestBuildSystem()

    self.workspace = Workspace(
      rootPath: nil,
      clientCapabilities: ClientCapabilities(),
      buildSettings: buildSystem,
      index: nil,
      buildSetup: TestSourceKitServer.serverOptions.buildSetup)
    testServer.server!.workspace = workspace

    sk = testServer.client
    _ = try! sk.sendSync(InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURL: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))
  }

  override func tearDown() {
    buildSystem = nil
    workspace = nil
    sk = nil
    testServer = nil
  }

  func testClangdDocumentUpdatedBuildSettings() {
    guard haveClangd else { return }

    let url = URL(fileURLWithPath: "/file.m")
    let args = [url.path, "-DDEBUG"]
    let text = """
    #ifdef FOO
    static void foo() {}
    #endif

    int main() {
      foo();
      return 0;
    }
    """

    buildSystem.buildSettingsByFile[url] = FileBuildSettings(compilerArguments: args)

    sk.allowUnexpectedNotification = false

    sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .objective_c,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnostics>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(text, self.workspace.documentManager.latestSnapshot(url)!.text)
    })

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    buildSystem.buildSettingsByFile[url] = FileBuildSettings(compilerArguments: args +  ["-DFOO"])
    testServer.server?.fileBuildSettingsChanged([url])

    let expectation = XCTestExpectation(description: "refresh")
    sk.handleNextNotification { (note: Notification<PublishDiagnostics>) in
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual(text, self.workspace.documentManager.latestSnapshot(url)!.text)
      expectation.fulfill()
    }

    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    if result != .completed {
      fatalError("error \(result) waiting for diagnostics notification")
    }
  }

  func testSwiftDocumentUpdatedBuildSettings() {
    let url = URL(fileURLWithPath: "/a.swift")
    let args = FallbackBuildSystem().settings(for: url, .swift)!.compilerArguments

    buildSystem.buildSettingsByFile[url] = FileBuildSettings(compilerArguments: args)

    let text = """
    #if FOO
    func foo() {}
    #endif

    foo()
    """

    sk.allowUnexpectedNotification = false

    sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnostics>) in
      // Syntactic analysis - no expected errors here.
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual(text, self.workspace.documentManager.latestSnapshot(url)!.text)
    }, { (note: Notification<PublishDiagnostics>) in
      // Semantic analysis - expect one error here.
      XCTAssertEqual(note.params.diagnostics.count, 1)
    })

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    buildSystem.buildSettingsByFile[url] = FileBuildSettings(compilerArguments: args + ["-DFOO"])

    let expectation = XCTestExpectation(description: "refresh")
    expectation.expectedFulfillmentCount = 2
    sk.handleNextNotification { (note: Notification<PublishDiagnostics>) in
      // Semantic analysis - SourceKit currently caches diagnostics so we still see an error.
      XCTAssertEqual(note.params.diagnostics.count, 1)
      expectation.fulfill()
    }
    sk.appendOneShotNotificationHandler  { (note: Notification<PublishDiagnostics>) in
      // Semantic analysis - no expected errors here because we fixed the settings.
      XCTAssertEqual(note.params.diagnostics.count, 0)
      expectation.fulfill()
    }
    testServer.server?.fileBuildSettingsChanged([url])

    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    if result != .completed {
      fatalError("error \(result) waiting for diagnostics notification")
    }
  }

  func testSwiftDocumentBuildSettingsChangedFalseAlarm() {
    let url = URL(fileURLWithPath: "/a.swift")

    sk.allowUnexpectedNotification = false

    sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: """
      func
      """
    )), { (note: Notification<PublishDiagnostics>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual("func", self.workspace.documentManager.latestSnapshot(url)!.text)
    })

    // Modify the build settings and inform the SourceKitServer.
    // This shouldn't trigger new diagnostics since nothing actually changed (false alarm).
    testServer.server?.fileBuildSettingsChanged([url])

    let expectation = XCTestExpectation(description: "refresh doesn't occur")
    expectation.isInverted = true
    sk.handleNextNotification { (note: Notification<PublishDiagnostics>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual("func", self.workspace.documentManager.latestSnapshot(url)!.text)
      expectation.fulfill()
    }

    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    if result != .completed {
      fatalError("error \(result) waiting for diagnostics notification")
    }
  }
}
