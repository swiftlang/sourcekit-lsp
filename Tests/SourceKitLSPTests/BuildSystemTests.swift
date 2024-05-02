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
@_spi(Testing) import SKCore
import SKTestSupport
@_spi(Testing) import SourceKitLSP
import TSCBasic
import XCTest

/// Build system to be used for testing BuildSystem and BuildSystemDelegate functionality with SourceKitLSPServer
/// and other components.
final class TestBuildSystem: BuildSystem {
  var projectRoot: AbsolutePath = try! AbsolutePath(validating: "/")
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

  public func defaultLanguage(for document: DocumentURI) async -> Language? {
    return nil
  }

  func registerForChangeNotifications(for uri: DocumentURI) async {
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

  func sourceFiles() async -> [SourceFileInfo] {
    return []
  }

  func addSourceFilesDidChangeCallback(_ callback: @escaping () async -> Void) async {}
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

  /// The build system that we use to verify SourceKitLSPServer behavior.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var buildSystem: TestBuildSystem! = nil

  /// Whether clangd exists in the toolchain.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var haveClangd: Bool = false

  override func setUp() async throws {
    testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    buildSystem = TestBuildSystem()

    let server = testClient.server

    self.workspace = await Workspace(
      documentManager: DocumentManager(),
      rootUri: nil,
      capabilityRegistry: CapabilityRegistry(clientCapabilities: ClientCapabilities()),
      toolchainRegistry: ToolchainRegistry.forTesting,
      options: SourceKitLSPServer.Options.testDefault,
      underlyingBuildSystem: buildSystem,
      index: nil,
      indexDelegate: nil,
      indexTaskScheduler: .forTesting
    )

    await server.setWorkspaces([(workspace: workspace, isImplicit: false)])
    await workspace.buildSystemManager.setDelegate(server)
  }

  override func tearDown() {
    buildSystem = nil
    workspace = nil
    testClient = nil
  }

  // MARK: - Tests

  func testClangdDocumentUpdatedBuildSettings() async throws {
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
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = FileBuildSettings(compilerArguments: args + ["-DFOO"])
    buildSystem.buildSettingsByFile[doc] = newSettings

    await buildSystem.delegate?.fileBuildSettingsChanged([doc])

    var receivedCorrectDiagnostic = false
    for _ in 0..<Int(defaultTimeout) {
      let refreshedDiags = try await testClient.nextDiagnosticsNotification(timeout: 1)
      if refreshedDiags.diagnostics.count == 0, try text == documentManager.latestSnapshot(doc).text {
        receivedCorrectDiagnostic = true
        break
      }
    }
    XCTAssert(receivedCorrectDiagnostic)
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
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

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
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should see a diagnostic.
    let newSettings = FileBuildSettings(compilerArguments: args)
    buildSystem.buildSettingsByFile[doc] = newSettings

    await buildSystem.delegate?.fileBuildSettingsChanged([doc])

    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)
  }

  func testSwiftDocumentFallbackWithholdsSemanticDiagnostics() async throws {
    let doc = DocumentURI.for(.swift)

    // Primary settings must be different than the fallback settings.
    var primarySettings = FallbackBuildSystem(buildSetup: .default).buildSettings(for: doc, language: .swift)!
    primarySettings.isFallback = false
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
    _ = try await testClient.nextNotification(ofType: ShowMessageNotification.self)
    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Swap from fallback settings to primary build system settings.
    buildSystem.buildSettingsByFile[doc] = primarySettings

    await buildSystem.delegate?.fileBuildSettingsChanged([doc])

    // Two errors since `-DFOO` was not passed.
    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 2)
  }
}
