//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import BuildServerIntegration
package import Foundation
package import LanguageServerProtocol
import SKLogging
import SKOptions
import SourceKitLSP
import SwiftExtensions
import TSCBasic
import ToolchainRegistry

package struct WindowsPlatformInfo {
  package struct DefaultProperties {
    /// XCTEST_VERSION
    /// specifies the version string of the bundled XCTest.
    public let xctestVersion: String

    /// SWIFT_TESTING_VERSION
    /// specifies the version string of the bundled swift-testing.
    public let swiftTestingVersion: String?

    /// SWIFTC_FLAGS
    /// Specifies extra flags to pass to swiftc from Swift Package Manager.
    public let extraSwiftCFlags: [String]?
  }

  public let defaults: DefaultProperties
}
extension WindowsPlatformInfo.DefaultProperties: Decodable {
  enum CodingKeys: String, CodingKey {
    case xctestVersion = "XCTEST_VERSION"
    case swiftTestingVersion = "SWIFT_TESTING_VERSION"
    case extraSwiftCFlags = "SWIFTC_FLAGS"
  }
}
extension WindowsPlatformInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case defaults = "DefaultProperties"
  }
}
extension WindowsPlatformInfo {
  package init(reading path: URL) throws {
    let data: Data = try Data(contentsOf: path)
    self = try PropertyListDecoder().decode(WindowsPlatformInfo.self, from: data)
  }
}
package struct IndexedSingleSwiftFileTestProject {
  enum Error: Swift.Error {
    case swiftcNotFound
  }

  package let testClient: TestSourceKitLSPClient
  package let fileURI: DocumentURI
  package let positions: DocumentPositions

  /// Writes a single file to a temporary directory on disk and compiles it to index it.
  ///
  /// - Parameters:
  ///   - markedText: The contents of the source file including location markers.
  ///   - allowBuildFailure: Whether to fail if the input source file fails to build or whether to continue the test
  ///     even if the input source is invalid.
  ///   - workspaceDirectory: If specified, the temporary files will be put in this directory. If `nil` a temporary
  ///     scratch directory will be created based on `testName`.
  ///   - cleanUp: Whether to remove the temporary directory when the SourceKit-LSP server shuts down.
  package init(
    _ markedText: String,
    capabilities: ClientCapabilities = ClientCapabilities(),
    indexSystemModules: Bool = false,
    allowBuildFailure: Bool = false,
    workspaceDirectory: URL? = nil,
    cleanUp: Bool = cleanScratchDirectories,
    testName: String = #function
  ) async throws {
    let testWorkspaceDirectory = try workspaceDirectory ?? testScratchDir(testName: testName)

    let testFileURL = testWorkspaceDirectory.appending(component: "test.swift")
    let indexURL = testWorkspaceDirectory.appending(component: "index")
    guard let swiftc = await ToolchainRegistry.forTesting.default?.swiftc else {
      throw Error.swiftcNotFound
    }

    // Create workspace with source file and compile_commands.json

    try extractMarkers(markedText).textWithoutMarkers.write(to: testFileURL, atomically: false, encoding: .utf8)

    var compilerArguments: [String] = [
      try testFileURL.filePath,
      "-index-store-path", try indexURL.filePath,
      "-typecheck",
    ]
    if let globalModuleCache = try globalModuleCache {
      compilerArguments += [
        "-module-cache-path", try globalModuleCache.filePath,
      ]
    }
    if !indexSystemModules {
      compilerArguments.append("-index-ignore-system-modules")
    }

    if let sdk = defaultSDKPath {
      compilerArguments += ["-sdk", sdk]

      // The following are needed so we can import XCTest
      let sdkUrl = URL(fileURLWithPath: sdk)
      #if os(Windows)
      let platform = sdkUrl.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      let info = try WindowsPlatformInfo(reading: platform.appending(component: "Info.plist"))
      let xctestModuleDir =
        platform
        .appending(
          components: "Developer",
          "Library",
          "XCTest-\(info.defaults.xctestVersion)",
          "usr",
          "lib",
          "swift",
          "windows"
        )
      compilerArguments += ["-I", try xctestModuleDir.filePath]
      #else
      let usrLibDir =
        sdkUrl
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(components: "usr", "lib")
      let frameworksDir =
        sdkUrl
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(components: "Library", "Frameworks")
      compilerArguments += [
        "-I", try usrLibDir.filePath,
        "-F", try frameworksDir.filePath,
      ]
      #endif
    }

    let compilationDatabase = JSONCompilationDatabase(
      [
        CompilationDatabaseCompileCommand(
          directory: try testWorkspaceDirectory.filePath,
          filename: try testFileURL.filePath,
          commandLine: [try swiftc.filePath] + compilerArguments
        )
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(compilationDatabase).write(
      to: testWorkspaceDirectory.appending(component: JSONCompilationDatabaseBuildServer.dbName)
    )

    // Run swiftc to build the index store
    do {
      let compilerArgumentsCopy = compilerArguments
      let output = try await withTimeout(defaultTimeoutDuration) {
        try await Process.checkNonZeroExit(arguments: [swiftc.filePath] + compilerArgumentsCopy)
      }
      logger.debug("swiftc output:\n\(output)")
    } catch {
      if !allowBuildFailure {
        throw error
      }
    }

    // Create the test client
    self.testClient = try await TestSourceKitLSPClient(
      options: try await SourceKitLSPOptions.testDefault(),
      capabilities: capabilities,
      workspaceFolders: [
        WorkspaceFolder(uri: DocumentURI(testWorkspaceDirectory))
      ],
      cleanUp: {
        if cleanUp {
          try? FileManager.default.removeItem(at: testWorkspaceDirectory)
        }
      }
    )

    // Wait for the indexstore-db to finish indexing
    try await testClient.send(SynchronizeRequest(index: true))

    // Open the document
    self.fileURI = DocumentURI(testFileURL)
    self.positions = testClient.openDocument(markedText, uri: fileURI)
  }
}
