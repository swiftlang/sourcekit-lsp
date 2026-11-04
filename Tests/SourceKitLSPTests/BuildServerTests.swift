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

@_spi(Testing) import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
import SKLogging
import SKOptions
import SKTestSupport
@_spi(Testing) import SemanticIndex
import SourceKitD
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
@_spi(Testing) import SwiftLanguageService
import TSCBasic
import Testing
import ToolchainRegistry
import XCTest

fileprivate actor TestBuildServer: CustomBuildServer {
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
    return dummyTargetSourcesResponse(files: buildSettingsByFile.keys)
  }

  func textDocumentSourceKitOptionsRequest(
    _ request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    return buildSettingsByFile[request.textDocument.uri]
  }
}

/// A build server that only reports the toolchain of its target once `setToolchain` is called.
fileprivate actor BuildServerWithLateToolchain: CustomBuildServer {
  let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
  private let projectRoot: URL
  private let connectionToSourceKitLSP: any Connection
  private var toolchain: URI? = nil

  func setToolchain(_ toolchain: URI) {
    self.toolchain = toolchain
    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
    self.projectRoot = projectRoot
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
  }

  func workspaceBuildTargetsRequest(
    _ request: WorkspaceBuildTargetsRequest
  ) async throws -> WorkspaceBuildTargetsResponse {
    return WorkspaceBuildTargetsResponse(targets: [
      BuildTarget(
        id: .dummy,
        capabilities: BuildTargetCapabilities(),
        languageIds: [.swift],
        dependencies: [],
        dataKind: .sourceKit,
        data: SourceKitBuildTarget(toolchain: toolchain).encodeToLSPAny()
      )
    ])
  }

  func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) -> BuildTargetSourcesResponse {
    return dummyTargetSourcesResponse(files: [DocumentURI(projectRoot.appending(component: "test.swift"))])
  }

  func textDocumentSourceKitOptionsRequest(
    _ request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    let settings = try XCTUnwrap(
      fallbackBuildSettings(
        for: request.textDocument.uri,
        language: .swift,
        options: SourceKitLSPOptions.FallbackBuildSystemOptions()
      )
    )
    return TextDocumentSourceKitOptionsResponse(
      compilerArguments: settings.compilerArguments,
      workingDirectory: settings.workingDirectory
    )
  }
}

final class BuildServerTests: SourceKitLSPTestCase {
  func testClangdDocumentUpdatedBuildSettings() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "test.c": """
        #ifdef FOO
        static void foo() {}
        #endif

        int main() {
          foo();
          return 0;
        }
        """
      ],
      buildServer: TestBuildServer.self,
      usePullDiagnostics: false
    )

    let args = [try project.uri(for: "test.c").pseudoPath, "-DDEBUG"]
    try await project.buildServer().setBuildSettings(
      for: project.uri(for: "test.c"),
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: args)
    )

    let (uri, _) = try project.openDocument("test.c")

    let diags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = TextDocumentSourceKitOptionsResponse(compilerArguments: args + ["-DFOO"])
    try await project.buildServer().setBuildSettings(for: uri, to: newSettings)

    try await repeatUntilExpectedResult {
      guard let refreshedDiags = try? await project.testClient.nextDiagnosticsNotification(timeout: .seconds(1)) else {
        return false
      }
      return refreshedDiags.diagnostics.count == 0
    }
  }

  func testSwiftDocumentUpdatedBuildSettings() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "test.swift": """
        #if FOO
        func foo() {}
        #endif

        foo()
        """
      ],
      buildServer: TestBuildServer.self,
      usePullDiagnostics: false
    )

    let args = try XCTUnwrap(
      fallbackBuildSettings(
        for: project.uri(for: "test.swift"),
        language: .swift,
        options: SourceKitLSPOptions.FallbackBuildSystemOptions()
      )
    ).compilerArguments

    try await project.buildServer().setBuildSettings(
      for: project.uri(for: "test.swift"),
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: args)
    )

    let (uri, _) = try project.openDocument("test.swift")
    let diags1 = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags1.diagnostics.count, 1)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should no longer have errors.
    let newSettings = TextDocumentSourceKitOptionsResponse(compilerArguments: args + ["-DFOO"])
    try await project.buildServer().setBuildSettings(for: uri, to: newSettings)

    // No expected errors here because we fixed the settings.
    let diags2 = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags2.diagnostics.count, 0)
  }

  func testClangdDocumentFallbackWithholdsDiagnostics() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "test.c": """
        #ifdef FOO
        static void foo() {}
        #endif

        int main() {
          foo();
          return 0;
        }
        """
      ],
      buildServer: TestBuildServer.self,
      usePullDiagnostics: false
    )

    let args = [try project.uri(for: "test.c").pseudoPath, "-DDEBUG"]

    let (uri, _) = try project.openDocument("test.c")
    let openDiags = try await project.testClient.nextDiagnosticsNotification()
    // Expect diagnostics to be withheld.
    XCTAssertEqual(openDiags.diagnostics.count, 0)

    // Modify the build settings and inform the delegate.
    // This should trigger a new publish diagnostics and we should see a diagnostic.
    let newSettings = TextDocumentSourceKitOptionsResponse(compilerArguments: args)
    try await project.buildServer().setBuildSettings(for: uri, to: newSettings)

    let refreshedDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 1)
  }

  func testSwiftDocumentFallbackWithholdsSemanticDiagnostics() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "test.swift": """
        #if FOO
        func foo() {}
        #endif

        foo()
        func
        """
      ],
      buildServer: TestBuildServer.self,
      usePullDiagnostics: false
    )

    // Primary settings must be different than the fallback settings.
    let fallbackSettings = try XCTUnwrap(
      fallbackBuildSettings(
        for: project.uri(for: "test.swift"),
        language: .swift,
        options: SourceKitLSPOptions.FallbackBuildSystemOptions()
      )
    )
    let primarySettings = TextDocumentSourceKitOptionsResponse(
      compilerArguments: fallbackSettings.compilerArguments + ["-DPRIMARY"],
      workingDirectory: fallbackSettings.workingDirectory
    )

    let (uri, _) = try project.openDocument("test.swift")
    let openDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)

    // Swap from fallback settings to primary build server settings.
    try await project.buildServer().setBuildSettings(for: uri, to: primarySettings)

    // Two errors since `-DFOO` was not passed.
    let refreshedDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(refreshedDiags.diagnostics.count, 2)
  }

  func testOpenDocumentMovesToToolchainReportedAfterOpen() async throws {
    // The preferred toolchain, which is used while the build server doesn't report a toolchain for the target. Its
    // sourcekitd doesn't exist, so it can't provide any functionality.
    let brokenDefaultToolchain = Toolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
      displayName: "broken",
      path: URL(fileURLWithPath: "/broken"),
      swift: URL(fileURLWithPath: "/broken/usr/bin/swift"),
      swiftc: URL(fileURLWithPath: "/broken/usr/bin/swiftc"),
      sourcekitd: URL(fileURLWithPath: "/broken/usr/lib/sourcekitd.framework/sourcekitd")
    )
    let workingToolchain = try await unwrap(ToolchainRegistry.forTesting.default)
    let project = try await CustomBuildServerTestProject(
      files: [
        "test.swift": """
        func
        """
      ],
      buildServer: BuildServerWithLateToolchain.self,
      toolchainRegistry: ToolchainRegistry(toolchains: [brokenDefaultToolchain, workingToolchain])
    )

    let (uri, _) = try project.openDocument("test.swift")
    await assertThrowsError(
      try await project.testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))
    )

    try await project.buildServer().setToolchain(URI(workingToolchain.path))

    try await repeatUntilExpectedResult {
      let diagnostics = try? await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diagnostics?.fullReport?.items.isEmpty == false
    }
  }

  func testOpenDocumentMovesBetweenWorkingToolchains() async throws {
    let toolchainA = try await unwrap(ToolchainRegistry.forTesting.default)
    let sourcekitdA = try unwrap(toolchainA.sourcekitd)
    // Pre-load sourcekitd so that the injected core below borrows a fully initialized dylib.
    _ = try await SourceKitD.getOrCreate(dylibPath: sourcekitdA, pluginPaths: sourceKitPluginPaths)

    // A second working toolchain. Its sourcekitd path differs from A's, so it gets its own `SwiftLanguageService`,
    // which talks to A's sourcekitd through an injected core. It contains fewer tools than A, so A remains the
    // preferred toolchain.
    let toolchainB = Toolchain(
      identifier: "second",
      displayName: "second",
      path: URL(fileURLWithPath: "/\(UUID())/second.xctoolchain"),
      swift: toolchainA.swift,
      swiftc: toolchainA.swiftc,
      sourcekitd: URL(fileURLWithPath: "/\(UUID())/sourcekitd"),
      sourceKitClientPlugin: toolchainA.sourceKitClientPlugin,
      sourceKitServicePlugin: toolchainA.sourceKitServicePlugin
    )
    let coreB = try InjectedSourceKitDCore(realDylibPath: sourcekitdA)

    let project = try await CustomBuildServerTestProject(
      files: [
        "test.swift": """
        func
        """
      ],
      buildServer: BuildServerWithLateToolchain.self,
      toolchainRegistry: ToolchainRegistry(toolchains: [toolchainA, toolchainB]),
      hooks: Hooks(sourcekitdCoreInjector: { toolchainPath in
        toolchainPath == toolchainB.path ? coreB : nil
      })
    )

    let (uri, _) = try project.openDocument("test.swift")
    let serviceA = try await unwrap(project.testClient.primaryLanguageService(for: uri) as? SwiftLanguageService)
    let coreA = await serviceA.sourcekitd.core
    XCTAssert(coreA as AnyObject !== coreB)

    try await project.buildServer().setToolchain(URI(toolchainB.path))

    try await repeatUntilExpectedResult {
      guard
        let service = try? await project.testClient.primaryLanguageService(for: uri) as? SwiftLanguageService
      else {
        return false
      }
      return await service.sourcekitd.core as AnyObject === coreB
    }
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(diagnostics.fullReport?.items.isEmpty, false)
  }
}
