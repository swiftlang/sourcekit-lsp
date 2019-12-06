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

import BuildServerProtocol
import LanguageServerProtocol
import LSPTestSupport
import SKCore
import SKTestSupport
import SourceKit
import TSCBasic
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
  var buildSettingsByFile: [DocumentURI: FileBuildSettings] = [:]

  /// Toolchains by file.
  var toolchainsByFile: [DocumentURI: Toolchain] = [:]

  /// Files currently being watched by our delegate.
  var watchedFiles: Set<DocumentURI> = []

  func settings(for uri: DocumentURI, _ language: Language) -> FileBuildSettings? {
    return buildSettingsByFile[uri]
  }

  func toolchain(for uri: DocumentURI, _ language: Language) -> Toolchain? {
    return toolchainsByFile[uri]
  }

  func registerForChangeNotifications(for uri: DocumentURI) {
    watchedFiles.insert(uri)
  }

  func unregisterForChangeNotifications(for uri: DocumentURI) {
    watchedFiles.remove(uri)
  }

  func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  func buildTargetSources(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[SourcesItem]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  func buildTargetOutputPaths(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[OutputsItem]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
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
      rootUri: nil,
      clientCapabilities: ClientCapabilities(),
      buildSettings: buildSystem,
      index: nil,
      buildSetup: TestSourceKitServer.serverOptions.buildSetup)
    testServer.server!.workspace = workspace

    sk = testServer.client
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

    buildSystem.buildSettingsByFile[DocumentURI(url)] = FileBuildSettings(compilerArguments: args)

    sk.allowUnexpectedNotification = false

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .objective_c,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(text, self.workspace.documentManager.latestSnapshot(DocumentURI(url))!.text)
    })

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    buildSystem.buildSettingsByFile[DocumentURI(url)] = FileBuildSettings(compilerArguments: args +  ["-DFOO"])
    testServer.server?.fileBuildSettingsChanged([DocumentURI(url)])

    let expectation = XCTestExpectation(description: "refresh")
    sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual(text, self.workspace.documentManager.latestSnapshot(DocumentURI(url))!.text)
      expectation.fulfill()
    }

    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    if result != .completed {
      fatalError("error \(result) waiting for diagnostics notification")
    }
  }

  func testSwiftDocumentUpdatedBuildSettings() {
    let url = URL(fileURLWithPath: "/a.swift")
    let args = FallbackBuildSystem().settings(for: DocumentURI(url), .swift)!.compilerArguments

    buildSystem.buildSettingsByFile[DocumentURI(url)] = FileBuildSettings(compilerArguments: args)

    let text = """
    #if FOO
    func foo() {}
    #endif

    foo()
    """

    sk.allowUnexpectedNotification = false

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .swift,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      // Syntactic analysis - no expected errors here.
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual(text, self.workspace.documentManager.latestSnapshot(DocumentURI(url))!.text)
    }, { (note: Notification<PublishDiagnosticsNotification>) in
      // Semantic analysis - expect one error here.
      XCTAssertEqual(note.params.diagnostics.count, 1)
    })

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    buildSystem.buildSettingsByFile[DocumentURI(url)] = FileBuildSettings(compilerArguments: args + ["-DFOO"])

    let expectation = XCTestExpectation(description: "refresh")
    expectation.expectedFulfillmentCount = 2
    sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      // Semantic analysis - SourceKit currently caches diagnostics so we still see an error.
      XCTAssertEqual(note.params.diagnostics.count, 1)
      expectation.fulfill()
    }
    sk.appendOneShotNotificationHandler  { (note: Notification<PublishDiagnosticsNotification>) in
      // Semantic analysis - no expected errors here because we fixed the settings.
      XCTAssertEqual(note.params.diagnostics.count, 0)
      expectation.fulfill()
    }
    testServer.server?.fileBuildSettingsChanged([DocumentURI(url)])

    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    if result != .completed {
      fatalError("error \(result) waiting for diagnostics notification")
    }
  }

  func testSwiftDocumentBuildSettingsChangedFalseAlarm() {
    let url = URL(fileURLWithPath: "/a.swift")

    sk.allowUnexpectedNotification = false

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .swift,
      version: 12,
      text: """
      func
      """
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual("func", self.workspace.documentManager.latestSnapshot(DocumentURI(url))!.text)
    })

    // Modify the build settings and inform the SourceKitServer.
    // This shouldn't trigger new diagnostics since nothing actually changed (false alarm).
    testServer.server?.fileBuildSettingsChanged([DocumentURI(url)])

    let expectation = XCTestExpectation(description: "refresh doesn't occur")
    expectation.isInverted = true
    sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual("func", self.workspace.documentManager.latestSnapshot(DocumentURI(url))!.text)
      expectation.fulfill()
    }

    let result = XCTWaiter.wait(for: [expectation], timeout: 1)
    if result != .completed {
      fatalError("error \(result) unexpected diagnostics notification")
    }
  }
}
