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
@_spi(Testing) import BuildSystemIntegration
import LanguageServerProtocol
import SKOptions
import SKTestSupport
@_spi(Testing) import SemanticIndex
@_spi(Testing) import SourceKitLSP
import TSCBasic
import ToolchainRegistry
import XCTest

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

    let server = testClient.server

    let buildSystemManager = await BuildSystemManager(
      buildSystemKind: .testBuildSystem(projectRoot: try AbsolutePath(validating: "/")),
      toolchainRegistry: .forTesting,
      options: .testDefault(),
      buildSystemTestHooks: BuildSystemTestHooks()
    )
    buildSystem = try await unwrap(buildSystemManager.buildSystem?.underlyingBuildSystem as? TestBuildSystem)

    self.workspace = await Workspace.forTesting(
      options: SourceKitLSPOptions.testDefault(),
      testHooks: TestHooks(),
      buildSystemManager: buildSystemManager,
      indexTaskScheduler: .forTesting
    )

    await server.setWorkspaces([(workspace: workspace, isImplicit: false)])
    await workspace.buildSystemManager.setDelegate(workspace)
  }

  override func tearDown() {
    buildSystem = nil
    workspace = nil
    testClient = nil
  }

  // MARK: - Tests

  func testClangdDocumentUpdatedBuildSettings() async throws {
    guard haveClangd else { return }

    let doc = DocumentURI(for: .objective_c)
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

    await buildSystem.setBuildSettings(for: doc, to: SourceKitOptionsResponse(compilerArguments: args))

    let documentManager = await self.testClient.server.documentManager

    testClient.openDocument(text, uri: doc)

    let diags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = SourceKitOptionsResponse(compilerArguments: args + ["-DFOO"])
    await buildSystem.setBuildSettings(for: doc, to: newSettings)

    try await repeatUntilExpectedResult {
      let refreshedDiags = try await testClient.nextDiagnosticsNotification(timeout: .seconds(1))
      return try text == documentManager.latestSnapshot(doc).text && refreshedDiags.diagnostics.count == 0
    }
  }

  func testSwiftDocumentUpdatedBuildSettings() async throws {
    let doc = DocumentURI(for: .swift)
    let args = await FallbackBuildSystem(options: SourceKitLSPOptions.FallbackBuildSystemOptions())
      .buildSettings(for: doc, language: .swift)!
      .compilerArguments

    await buildSystem.setBuildSettings(for: doc, to: SourceKitOptionsResponse(compilerArguments: args))

    let text = """
      #if FOO
      func foo() {}
      #endif

      foo()
      """

    let documentManager = await self.testClient.server.documentManager

    testClient.openDocument(text, uri: doc)
    let diags1 = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags1.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = SourceKitOptionsResponse(compilerArguments: args + ["-DFOO"])
    await buildSystem.setBuildSettings(for: doc, to: newSettings)

    // No expected errors here because we fixed the settings.
    let diags2 = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags2.diagnostics.count, 0)
  }

  func testClangdDocumentFallbackWithholdsDiagnostics() async throws {
    let doc = DocumentURI(for: .objective_c)
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

    let documentManager = await self.testClient.server.documentManager

    testClient.openDocument(text, uri: doc)
    let openDiags = try await testClient.nextDiagnosticsNotification()
    // Expect diagnostics to be withheld.
    XCTAssertEqual(openDiags.diagnostics.count, 0)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should see a diagnostic.
    let newSettings = SourceKitOptionsResponse(compilerArguments: args)
    await buildSystem.setBuildSettings(for: doc, to: newSettings)

    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)
  }

  func testSwiftDocumentFallbackWithholdsSemanticDiagnostics() async throws {
    let doc = DocumentURI(for: .swift)

    // Primary settings must be different than the fallback settings.
    let fallbackSettings = await FallbackBuildSystem(options: SourceKitLSPOptions.FallbackBuildSystemOptions())
      .buildSettings(for: doc, language: .swift)!
    let primarySettings = SourceKitOptionsResponse(
      compilerArguments: fallbackSettings.compilerArguments + ["-DPRIMARY"],
      workingDirectory: fallbackSettings.workingDirectory
    )

    let text = """
        #if FOO
        func foo() {}
        #endif

        foo()
        func
      """

    let documentManager = await self.testClient.server.documentManager

    testClient.openDocument(text, uri: doc)
    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Swap from fallback settings to primary build system settings.
    await buildSystem.setBuildSettings(for: doc, to: primarySettings)

    // Two errors since `-DFOO` was not passed.
    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 2)
  }
}
