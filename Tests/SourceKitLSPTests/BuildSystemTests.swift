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
import LanguageServerProtocolExtensions
import SKOptions
import SKTestSupport
@_spi(Testing) import SemanticIndex
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
import XCTest

fileprivate actor TestBuildSystem: CustomBuildServer {
  let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
  private let connectionToSourceKitLSP: any Connection
  private var buildSettingsByFile: [DocumentURI: TextDocumentSourceKitOptionsResponse] = [:]

  func setBuildSettings(for uri: DocumentURI, to buildSettings: TextDocumentSourceKitOptionsResponse?) {
    buildSettingsByFile[uri] = buildSettings
    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
  }

  func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) -> BuildTargetSourcesResponse {
    return dummyTargetSourcesResponse(buildSettingsByFile.keys)
  }

  func textDocumentSourceKitOptionsRequest(
    _ request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    return buildSettingsByFile[request.textDocument.uri]
  }
}

final class BuildSystemTests: XCTestCase {
  /// The mock client used to communicate with the SourceKit-LSP server.p
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

    let testBuildSystem = ThreadSafeBox<TestBuildSystem?>(initialValue: nil)
    let buildSystemManager = await BuildSystemManager(
      buildSystemSpec: BuildSystemSpec(
        kind: .injected({ projectRoot, connectionToSourceKitLSP in
          assert(testBuildSystem.value == nil, "Build system injector hook can only create a single TestBuildSystem")
          let buildSystem = TestBuildSystem(
            projectRoot: projectRoot,
            connectionToSourceKitLSP: connectionToSourceKitLSP
          )
          testBuildSystem.value = buildSystem
          return LocalConnection(receiverName: "TestBuildSystem", handler: buildSystem)
        }),
        projectRoot: URL(fileURLWithPath: "/"),
        configPath: URL(fileURLWithPath: "/")
      ),
      toolchainRegistry: .forTesting,
      options: try .testDefault(),
      connectionToClient: DummyBuildSystemManagerConnectionToClient(),
      buildSystemHooks: BuildSystemHooks()
    )
    buildSystem = try unwrap(testBuildSystem.value)

    self.workspace = await Workspace.forTesting(
      options: try .testDefault(),
      testHooks: Hooks(),
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

    await buildSystem.setBuildSettings(for: doc, to: TextDocumentSourceKitOptionsResponse(compilerArguments: args))

    let documentManager = await self.testClient.server.documentManager

    testClient.openDocument(text, uri: doc)

    let diags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = TextDocumentSourceKitOptionsResponse(compilerArguments: args + ["-DFOO"])
    await buildSystem.setBuildSettings(for: doc, to: newSettings)

    try await repeatUntilExpectedResult {
      guard let refreshedDiags = try? await testClient.nextDiagnosticsNotification(timeout: .seconds(1)) else {
        return false
      }
      return try text == documentManager.latestSnapshot(doc).text && refreshedDiags.diagnostics.count == 0
    }
  }

  func testSwiftDocumentUpdatedBuildSettings() async throws {
    let doc = DocumentURI(for: .swift)
    let args = fallbackBuildSettings(
      for: doc,
      language: .swift,
      options: SourceKitLSPOptions.FallbackBuildSystemOptions()
    )!.compilerArguments

    await buildSystem.setBuildSettings(for: doc, to: TextDocumentSourceKitOptionsResponse(compilerArguments: args))

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
    let newSettings = TextDocumentSourceKitOptionsResponse(compilerArguments: args + ["-DFOO"])
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
    let newSettings = TextDocumentSourceKitOptionsResponse(compilerArguments: args)
    await buildSystem.setBuildSettings(for: doc, to: newSettings)

    let refreshedDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 1)
    XCTAssertEqual(text, try documentManager.latestSnapshot(doc).text)
  }

  func testSwiftDocumentFallbackWithholdsSemanticDiagnostics() async throws {
    let doc = DocumentURI(for: .swift)

    // Primary settings must be different than the fallback settings.
    let fallbackSettings = fallbackBuildSettings(
      for: doc,
      language: .swift,
      options: SourceKitLSPOptions.FallbackBuildSystemOptions()
    )!
    let primarySettings = TextDocumentSourceKitOptionsResponse(
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
