//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import ToolchainRegistry

/// A SwiftPM project that is built from files specified inside the test case and that can provide compiler arguments
/// for those files.
///
/// Compared to `SwiftPMTestProject`, the main difference is that this does not start a SourceKit-LSP server.
final class PluginSwiftPMTestProject {
  /// The directory in which the temporary files are being placed.
  let scratchDirectory: URL

  private let fileData: [String: MultiFileTestProject.FileData]

  private var _buildServerManager: BuildServerManager?
  private var buildServerManager: BuildServerManager {
    get async throws {
      if let _buildServerManager {
        return _buildServerManager
      }
      let buildServerManager = await BuildServerManager(
        buildServerSpec: BuildServerSpec(
          kind: .swiftPM,
          projectRoot: scratchDirectory,
          configPath: scratchDirectory.appending(component: "Package.swift")
        ),
        toolchainRegistry: .forTesting,
        options: try .testDefault(backgroundIndexing: false),
        connectionToClient: DummyBuildServerManagerConnectionToClient(),
        buildServerHooks: BuildServerHooks(),
        createMainFilesProvider: { _, _ in nil }
      )
      _buildServerManager = buildServerManager
      return buildServerManager
    }
  }

  enum Error: Swift.Error {
    /// No file with the given filename is known to the `PluginSwiftPMTestProject`.
    case fileNotFound

    /// `PluginSwiftPMTestProject` did not produce compiler arguments for a file.
    case failedToRetrieveCompilerArguments
  }

  package init(
    files: [RelativeFileLocation: String],
    testName: String = #function
  ) async throws {
    scratchDirectory = try testScratchDir(testName: testName)
    self.fileData = try MultiFileTestProject.writeFilesToDisk(files: files, scratchDirectory: scratchDirectory)

    // Build package
    try await SwiftPMTestProject.build(at: scratchDirectory)
  }

  deinit {
    if cleanScratchDirectories {
      try? FileManager.default.removeItem(at: scratchDirectory)
    }
  }

  /// Returns the URI of the file with the given name.
  package func uri(for fileName: String) throws -> DocumentURI {
    guard let fileData = self.fileData[fileName] else {
      throw Error.fileNotFound
    }
    return fileData.uri
  }

  /// Returns the position of the given marker in the given file.
  package func position(of marker: String, in fileName: String) throws -> Position {
    guard let fileData = self.fileData[fileName] else {
      throw Error.fileNotFound
    }
    return DocumentPositions(markedText: fileData.markedText)[marker]
  }

  /// Returns the contents of the file with the given name.
  package func contents(of fileName: String) throws -> String {
    guard let fileData = self.fileData[fileName] else {
      throw Error.fileNotFound
    }
    return extractMarkers(fileData.markedText).textWithoutMarkers
  }

  package func compilerArguments(for fileName: String) async throws -> [String] {
    try await buildServerManager.waitForUpToDateBuildGraph()
    let buildSettings = try await buildServerManager.buildSettingsInferredFromMainFile(
      for: try uri(for: fileName),
      language: .swift,
      fallbackAfterTimeout: false
    )
    guard let buildSettings else {
      throw Error.failedToRetrieveCompilerArguments
    }
    let compilerArguments = buildSettings.compilerArguments
    if compilerArguments.first?.hasSuffix("swiftc") ?? false {
      // Compiler arguments returned from SwiftPMWorkspace contain the compiler executable.
      // sourcekitd does not expect the compiler arguments to contain the executable.
      return Array(compilerArguments.dropFirst())
    }
    return compilerArguments
  }
}
