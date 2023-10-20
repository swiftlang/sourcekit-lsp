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
import LSPTestSupport
import LanguageServerProtocol
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

  public func setDelegate(_ delegate: BuildSystemDelegate?) async {
    self.delegate = delegate
  }

  /// Build settings by file.
  var buildSettingsByFile: [DocumentURI: FileBuildSettings] = [:]

  /// Files currently being watched by our delegate.
  var watchedFiles: Set<DocumentURI> = []

  func buildSettings(for document: DocumentURI, language: Language) async throws -> FileBuildSettings? {
    return buildSettingsByFile[document]
  }

  func registerForChangeNotifications(for uri: DocumentURI, language: Language) async {
    watchedFiles.insert(uri)
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

  /// The mock client used to communicate with the SourceKit-LSP server.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var testClient: TestSourceKitLSPClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var workspace: Workspace! = nil

  /// The build system that we use to verify SourceKitServer behavior.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var buildSystem: TestBuildSystem! = nil

  /// Whether clangd exists in the toolchain.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var haveClangd: Bool = false

  override func setUp() async throws {
    haveClangd = ToolchainRegistry.shared.toolchains.contains { $0.clangd != nil }
    testClient = try await TestSourceKitLSPClient()
    buildSystem = TestBuildSystem()

    let server = testClient.server

    self.workspace = await Workspace(
      documentManager: DocumentManager(),
      rootUri: nil,
      capabilityRegistry: CapabilityRegistry(clientCapabilities: ClientCapabilities()),
      toolchainRegistry: ToolchainRegistry.shared,
      buildSetup: SourceKitServer.Options.testDefault.buildSetup,
      underlyingBuildSystem: buildSystem,
      index: nil,
      indexDelegate: nil
    )

    await server.setWorkspaces([workspace])
    await workspace.buildSystemManager.setDelegate(server)
  }

  override func tearDown() {
    buildSystem = nil
    workspace = nil
    testClient = nil
  }

  // MARK: - Tests

  func testClangdDocumentUpdatedBuildSettings() async throws {
    try XCTSkipIf(true, "rdar://115435598 - crashing on rebranch")

    guard haveClangd else { return }

    let doc = DocumentURI.for(.objective_c)
    let args = [doc.pseudoPath, "-DDEBUG"]
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

    let documentManager = await self.testClient.server._documentManager

    testClient.openDocument(text, uri: doc)

    let diags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = FileBuildSettings(compilerArguments: args + ["-DFOO"])
    buildSystem.buildSettingsByFile[doc] = newSettings

    let expectation = XCTestExpectation(description: "refresh")
    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 0)
    XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)

    await buildSystem.delegate?.fileBuildSettingsChanged([doc])

    try await fulfillmentOfOrThrow([expectation])
  }

  func testSwiftDocumentUpdatedBuildSettings() async throws {
    let doc = DocumentURI.for(.swift)
    let args = FallbackBuildSystem(buildSetup: .default).buildSettings(for: doc, language: .swift)!.compilerArguments

    buildSystem.buildSettingsByFile[doc] = FileBuildSettings(compilerArguments: args)

    let text = """
      #if FOO
      func foo() {}
      #endif

      foo()
      """

    let documentManager = await self.testClient.server._documentManager

    testClient.openDocument(text, uri: doc)
    let diags1 = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags1.diagnostics.count, 1)
    XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = FileBuildSettings(compilerArguments: args + ["-DFOO"])
    buildSystem.buildSettingsByFile[doc] = newSettings

    await buildSystem.delegate?.fileBuildSettingsChanged([doc])

    // No expected errors here because we fixed the settings.
    let diags2 = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags2.diagnostics.count, 0)
  }

  func testClangdDocumentFallbackWithholdsDiagnostics() async throws {
    try XCTSkipIf(!haveClangd)

    let doc = DocumentURI.for(.objective_c)
    let args = [doc.pseudoPath, "-DDEBUG"]
    let text = """
        #ifdef FOO
        static void foo() {}
        #endif

        int main() {
          foo();
          return 0;
        }
      """

    let documentManager = await self.testClient.server._documentManager

    testClient.openDocument(text, uri: doc)
    let openDiags = try await testClient.nextDiagnosticsNotification()
    // Expect diagnostics to be withheld.
    XCTAssertEqual(openDiags.diagnostics.count, 0)
    XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should see a diagnostic.
    let newSettings = FileBuildSettings(compilerArguments: args)
    buildSystem.buildSettingsByFile[doc] = newSettings

    await buildSystem.delegate?.fileBuildSettingsChanged([doc])

    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 1)
    XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)
  }

  func testSwiftDocumentFallbackWithholdsSemanticDiagnostics() async throws {
    let doc = DocumentURI.for(.swift)

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

    let documentManager = await self.testClient.server._documentManager

    testClient.openDocument(text, uri: doc)
    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(text, documentManager.latestSnapshot(doc)!.text)

    // Swap from fallback settings to primary build system settings.
    buildSystem.buildSettingsByFile[doc] = primarySettings

    await buildSystem.delegate?.fileBuildSettingsChanged([doc])

    // Two errors since `-DFOO` was not passed.
    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 2)
  }

  func testMainFilesChanged() async throws {
    try XCTSkipIf(true, "rdar://115176405 - failing on rebranch due to extra published diagnostic")

    let ws = try await mutableSourceKitTibsTestWorkspace(name: "MainFiles")!
    let unique_h = ws.testLoc("unique").docIdentifier.uri

    try ws.openDocument(unique_h.fileURL!, language: .cpp)

    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 0)

    try ws.buildAndIndex()
    let diagsFromD = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diagsFromD.diagnostics.count, 1)
    let diagFromD = try XCTUnwrap(diagsFromD.diagnostics.first)
    XCTAssertEqual(diagFromD.severity, .warning)
    XCTAssertEqual(diagFromD.message, "UNIQUE_INCLUDED_FROM_D")

    try ws.edit(rebuild: true) { (changes, _) in
      changes.write(
        """
        // empty
        """,
        to: ws.testLoc("d_func").url
      )
      changes.write(
        """
        #include "unique.h"
        """,
        to: ws.testLoc("c_func").url
      )
    }

    let diagsFromC = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diagsFromC.diagnostics.count, 1)
    let diagFromC = try XCTUnwrap(diagsFromC.diagnostics.first)
    XCTAssertEqual(diagFromC.severity, .warning)
    XCTAssertEqual(diagFromC.message, "UNIQUE_INCLUDED_FROM_C")
  }

  private func clangBuildSettings(for uri: DocumentURI) -> FileBuildSettings {
    return FileBuildSettings(compilerArguments: [uri.pseudoPath, "-DDEBUG"])
  }
}
