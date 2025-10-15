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
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
import TSCBasic
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
}
