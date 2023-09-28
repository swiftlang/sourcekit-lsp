//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
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
import SourceKitLSP
import TSCBasic
import XCTest

fileprivate extension SourceKitServer {
  func setWorkspaces(_ workspaces: [Workspace]) {
    self._workspaces = workspaces
  }
}

// Workaround ambiguity with Foundation.
typealias LSPNotification = LanguageServerProtocol.Notification

/// Build system to be used for testing BuildSystem and BuildSystemDelegate functionality with SourceKitServer
/// and other components.
final class TestBuildSystem: BuildSystem {
  var indexStorePath: AbsolutePath? = nil
  var indexDatabasePath: AbsolutePath? = nil
  var indexPrefixMappings: [PathPrefixMapping] = []

  weak var delegate: BuildSystemDelegate?

  /// Build settings by file.
  var buildSettingsByFile: [DocumentURI: FileBuildSettings] = [:]

  /// Files currently being watched by our delegate.
  var watchedFiles: Set<DocumentURI> = []

  func buildSettings(for document: DocumentURI, language: Language) async throws -> FileBuildSettings? {
    return buildSettingsByFile[document]
  }

  func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    watchedFiles.insert(uri)

    // Inform our delegate of settings for the file if they're available.
    guard let delegate = self.delegate,
          let settings = self.buildSettingsByFile[uri] else {
      return
    }

    DispatchQueue.global().async {
      delegate.fileBuildSettingsChanged([uri: .modified(settings)])
    }
  }

  func unregisterForChangeNotifications(for uri: DocumentURI) {
    watchedFiles.remove(uri)
  }

  func filesDidChange(_ events: [FileEvent]) {}

  public func fileHandlingCapability(for uri: DocumentURI) -> FileHandlingCapability {
    if buildSettingsByFile[uri] != nil {
      return .handled
    } else {
      return .unhandled
    }
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
    // XCTestCase.setUp cannot be async, so unfortunately we need to do some
    // hackery to synchronously wait for a task to finish. This is very much an
    // anti-pattern because it can easily lead to priority inversions and should
    // thus not be copied to any non-test code.
    let sema = DispatchSemaphore(value: 0)
    Task {
      haveClangd = ToolchainRegistry.shared.toolchains.contains { $0.clangd != nil }
      testServer = TestSourceKitServer()
      buildSystem = TestBuildSystem()

      let server = testServer.server!

      self.workspace = Workspace(
        documentManager: DocumentManager(),
        rootUri: nil,
        capabilityRegistry: CapabilityRegistry(clientCapabilities: ClientCapabilities()),
        toolchainRegistry: ToolchainRegistry.shared,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup,
        underlyingBuildSystem: buildSystem,
        index: nil,
        indexDelegate: nil)


      await server.setWorkspaces([workspace])
      await workspace.buildSystemManager.setDelegate(server)

      sk = testServer.client
      _ = try! sk.sendSync(InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))
      sema.signal()
    }
    sema.wait()
  }

  override func tearDown() {
    buildSystem = nil
    workspace = nil
    sk = nil
    testServer = nil
  }

  func testClangdDocumentUpdatedBuildSettings() async throws {
    try XCTSkipIf(true, "rdar://115435598 - crashing on rebranch")

    guard haveClangd else { return }

#if os(Windows)
    let url = URL(fileURLWithPath: "C:/\(UUID())/file.m")
#else
    let url = URL(fileURLWithPath: "/\(UUID())/file.m")
#endif
    let doc = DocumentURI(url)
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

    buildSystem.buildSettingsByFile[doc] = FileBuildSettings(compilerArguments: args)

    sk.allowUnexpectedNotification = false

    let documentManager = await self.testServer.server!._documentManager

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: doc,
      language: .objective_c,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)
    })

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = FileBuildSettings(compilerArguments: args +  ["-DFOO"])
    buildSystem.buildSettingsByFile[doc] = newSettings

    let expectation = XCTestExpectation(description: "refresh")
    sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)
      expectation.fulfill()
    }

    buildSystem.delegate?.fileBuildSettingsChanged([doc: .modified(newSettings)])

    try await fulfillmentOfOrThrow([expectation])
  }

  func testSwiftDocumentUpdatedBuildSettings() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let doc = DocumentURI(url)
    let args = FallbackBuildSystem(buildSetup: .default).buildSettings(for: doc, language: .swift)!.compilerArguments

    buildSystem.buildSettingsByFile[doc] = FileBuildSettings(compilerArguments: args)

    let text = """
    #if FOO
    func foo() {}
    #endif

    foo()
    """

    sk.allowUnexpectedNotification = false

    let documentManager = await self.testServer.server!._documentManager

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: doc,
      language: .swift,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      // Syntactic analysis - no expected errors here.
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)
    }, { (note: Notification<PublishDiagnosticsNotification>) in
      // Semantic analysis - expect one error here.
      XCTAssertEqual(note.params.diagnostics.count, 1)
    })

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = FileBuildSettings(compilerArguments: args + ["-DFOO"])
    buildSystem.buildSettingsByFile[doc] = newSettings

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
    buildSystem.delegate?.fileBuildSettingsChanged([doc: .modified(newSettings)])

    try await fulfillmentOfOrThrow([expectation])
  }

  func testClangdDocumentFallbackWithholdsDiagnostics() async throws {
    try XCTSkipIf(!haveClangd)

#if os(Windows)
    let url = URL(fileURLWithPath: "C:/\(UUID())/file.m")
#else
    let url = URL(fileURLWithPath: "/\(UUID())/file.m")
#endif
    let doc = DocumentURI(url)
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

    sk.allowUnexpectedNotification = false

    let documentManager = await self.testServer.server!._documentManager

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: doc,
      language: .objective_c,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      // Expect diagnostics to be withheld.
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)
    })

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should see a diagnostic.
    let newSettings = FileBuildSettings(compilerArguments: args)
    buildSystem.buildSettingsByFile[doc] = newSettings

    let expectation = XCTestExpectation(description: "refresh due to fallback --> primary")
    sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)
      expectation.fulfill()
    }

    buildSystem.delegate?.fileBuildSettingsChanged([doc: .modified(newSettings)])

    try await fulfillmentOfOrThrow([expectation])
  }

  func testSwiftDocumentFallbackWithholdsSemanticDiagnostics() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let doc = DocumentURI(url)

    // Primary settings must be different than the fallback settings.
    var primarySettings = FallbackBuildSystem(buildSetup: .default).buildSettings(for: doc, language: .swift)!
    primarySettings.compilerArguments.append("-DPRIMARY")

    let text = """
      #if FOO
      func foo() {}
      #endif

      foo()
      func
    """

    sk.allowUnexpectedNotification = false

    let documentManager = await self.testServer.server!._documentManager

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: doc,
      language: .swift,
      version: 12,
      text: text
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      // Syntactic analysis - one expected errors here (for `func`).
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)
    }, { (note: Notification<PublishDiagnosticsNotification>) in
      // Should be the same syntactic analysis since we are using fallback arguments
      XCTAssertEqual(note.params.diagnostics.count, 1)
    })

    // Swap from fallback settings to primary build system settings.
    buildSystem.buildSettingsByFile[doc] = primarySettings
    let expectation = XCTestExpectation(description: "refresh due to fallback --> primary")
    expectation.expectedFulfillmentCount = 2
    sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      // Syntactic analysis with new args - one expected errors here (for `func`).
      XCTAssertEqual(note.params.diagnostics.count, 1)
      expectation.fulfill()
    }
    sk.appendOneShotNotificationHandler  { (note: Notification<PublishDiagnosticsNotification>) in
      // Semantic analysis - two errors since `-DFOO` was not passed.
      XCTAssertEqual(note.params.diagnostics.count, 2)
      expectation.fulfill()
    }
    buildSystem.delegate?.fileBuildSettingsChanged([doc: .modified(primarySettings)])

    try await fulfillmentOfOrThrow([expectation])
  }

  func testSwiftDocumentBuildSettingsChangedFalseAlarm() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let doc = DocumentURI(url)

    sk.allowUnexpectedNotification = false

    let documentManager = await self.testServer.server!._documentManager

    sk.sendNoteSync(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: doc,
      language: .swift,
      version: 12,
      text: """
      func
      """
    )), { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual("func", documentManager.latestSnapshot(doc)!.text)
    }, { (note: Notification<PublishDiagnosticsNotification>) in
      // Using fallback system, so we will receive the same syntactic diagnostics from before.
      XCTAssertEqual(note.params.diagnostics.count, 1)
    })

    // Modify the build settings and inform the SourceKitServer.
    // This shouldn't trigger new diagnostics since nothing actually changed (false alarm).
    buildSystem.delegate?.fileBuildSettingsChanged([doc: .removedOrUnavailable])

    let expectation = XCTestExpectation(description: "refresh doesn't occur")
    expectation.isInverted = true
    sk.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual("func", documentManager.latestSnapshot(doc)!.text)
      expectation.fulfill()
    }

    try await fulfillmentOfOrThrow([expectation], timeout: 1)
  }

  func testMainFilesChanged() async throws {
    try XCTSkipIf(true, "rdar://115176405 - failing on rebranch due to extra published diagnostic")

    let ws = try await mutableSourceKitTibsTestWorkspace(name: "MainFiles")!
    let unique_h = ws.testLoc("unique").docIdentifier.uri

    ws.testServer.client.allowUnexpectedNotification = false

    let expectation = self.expectation(description: "initial")
    ws.testServer.client.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      // Should withhold diagnostics since we should be using fallback arguments.
      XCTAssertEqual(note.params.diagnostics.count, 0)
      expectation.fulfill()
    }

    try ws.openDocument(unique_h.fileURL!, language: .cpp)
    try await fulfillmentOfOrThrow([expectation])

    let use_d = self.expectation(description: "update settings to d.cpp")
    ws.testServer.client.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      if let diag = note.params.diagnostics.first {
        XCTAssertEqual(diag.severity, .warning)
        XCTAssertEqual(diag.message, "UNIQUE_INCLUDED_FROM_D")
      }
      use_d.fulfill()
    }

    try ws.buildAndIndex()
    try await fulfillmentOfOrThrow([use_d])

    let use_c = self.expectation(description: "update settings to c.cpp")
    ws.testServer.client.handleNextNotification { (note: Notification<PublishDiagnosticsNotification>) in
      XCTAssertEqual(note.params.diagnostics.count, 1)
      if let diag = note.params.diagnostics.first {
        XCTAssertEqual(diag.severity, .warning)
        XCTAssertEqual(diag.message, "UNIQUE_INCLUDED_FROM_C")
      }
      use_c.fulfill()
    }

    try ws.edit(rebuild: true) { (changes, _) in
      changes.write("""
        // empty
        """, to: ws.testLoc("d_func").url)
      changes.write("""
        #include "unique.h"
        """, to: ws.testLoc("c_func").url)
    }

    try await fulfillmentOfOrThrow([use_c])
  }

  private func clangBuildSettings(for uri: DocumentURI) -> FileBuildSettings {
    return FileBuildSettings(compilerArguments: [uri.pseudoPath, "-DDEBUG"])
  }
}
