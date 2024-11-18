//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if compiler(>=6)
package import Foundation
package import LanguageServerProtocol
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
import XCTest
#else
import Foundation
import LanguageServerProtocol
import SKOptions
import SourceKitLSP
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
import XCTest
#endif

private struct SwiftSyntaxCShimsModulemapNotFoundError: Error {}

package class SwiftPMTestProject: MultiFileTestProject {
  enum Error: Swift.Error {
    /// The `swift` executable could not be found.
    case swiftNotFound
  }

  package static let defaultPackageManifest: String = """
    // swift-tools-version: 5.7

    import PackageDescription

    let package = Package(
      name: "MyLibrary",
      targets: [.target(name: "MyLibrary")]
    )
    """

  /// A manifest that defines two targets:
  ///  - A macro target named `MyMacro`
  ///  - And executable target named `MyMacroClient`
  ///
  /// It builds the macro using the swift-syntax that was already built as part of the SourceKit-LSP build.
  /// Re-using the SwiftSyntax modules that are already built is significantly faster than building swift-syntax in
  /// each test case run and does not require internet access.
  package static var macroPackageManifest: String {
    get async throws {
      // Directories that we should search for the swift-syntax package.
      // We prefer a checkout in the build folder. If that doesn't exist, we are probably using local dependencies
      // (SWIFTCI_USE_LOCAL_DEPS), so search next to the sourcekit-lsp source repo
      let swiftSyntaxSearchPaths = [
        productsDirectory
          .deletingLastPathComponent()  // arm64-apple-macosx
          .deletingLastPathComponent()  // debug
          .appendingPathComponent("checkouts"),
        URL(fileURLWithPath: #filePath)
          .deletingLastPathComponent()  // SwiftPMTestProject.swift
          .deletingLastPathComponent()  // SKTestSupport
          .deletingLastPathComponent()  // Sources
          .deletingLastPathComponent(),  // sourcekit-lsp
      ]

      let swiftSyntaxCShimsModulemap =
        swiftSyntaxSearchPaths.map { swiftSyntaxSearchPath in
          swiftSyntaxSearchPath
            .appendingPathComponent("swift-syntax")
            .appendingPathComponent("Sources")
            .appendingPathComponent("_SwiftSyntaxCShims")
            .appendingPathComponent("include")
            .appendingPathComponent("module.modulemap")
        }
        .first { FileManager.default.fileExists(at: $0) }

      guard let swiftSyntaxCShimsModulemap else {
        throw SwiftSyntaxCShimsModulemapNotFoundError()
      }

      let swiftSyntaxModulesToLink = [
        "SwiftBasicFormat",
        "SwiftCompilerPlugin",
        "SwiftCompilerPluginMessageHandling",
        "SwiftDiagnostics",
        "SwiftOperators",
        "SwiftParser",
        "SwiftParserDiagnostics",
        "SwiftSyntax",
        "SwiftSyntaxBuilder",
        "SwiftSyntaxMacroExpansion",
        "SwiftSyntaxMacros",
      ]

      var objectFiles: [String] = []
      for moduleName in swiftSyntaxModulesToLink {
        let dir = productsDirectory.appendingPathComponent("\(moduleName).build")
        let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
          if file.pathExtension == "o" {
            objectFiles.append(try file.filePath)
          }
        }
      }

      let linkerFlags = objectFiles.map {
        """
        "-l", "\($0)",
        """
      }.joined(separator: "\n")

      let moduleSearchPath: String
      if let toolchainVersion = try await ToolchainRegistry.forTesting.default?.swiftVersion,
        toolchainVersion < SwiftVersion(6, 0)
      {
        moduleSearchPath = try productsDirectory.filePath
      } else {
        moduleSearchPath = "\(try productsDirectory.filePath)/Modules"
      }

      return """
        // swift-tools-version: 5.10

        import PackageDescription
        import CompilerPluginSupport

        let package = Package(
          name: "MyMacro",
          platforms: [.macOS(.v10_15)],
          targets: [
            .macro(
              name: "MyMacros",
              swiftSettings: [.unsafeFlags([
                "-I", "\(moduleSearchPath)",
                "-Xcc", "-fmodule-map-file=\(try swiftSyntaxCShimsModulemap.filePath)"
              ])],
              linkerSettings: [
                .unsafeFlags([
                  \(linkerFlags)
                ])
              ]
            ),
            .executableTarget(name: "MyMacroClient", dependencies: ["MyMacros"]),
          ]
        )
        """
    }
  }

  /// Create a new SwiftPM package with the given files.
  ///
  /// If `index` is `true`, then the package will be built, indexing all modules within the package.
  package init(
    files: [RelativeFileLocation: String],
    manifest: String = SwiftPMTestProject.defaultPackageManifest,
    workspaces: (URL) async throws -> [WorkspaceFolder] = { [WorkspaceFolder(uri: DocumentURI($0))] },
    initializationOptions: LSPAny? = nil,
    capabilities: ClientCapabilities = ClientCapabilities(),
    options: SourceKitLSPOptions = .testDefault(),
    testHooks: TestHooks = TestHooks(),
    enableBackgroundIndexing: Bool = false,
    usePullDiagnostics: Bool = true,
    pollIndex: Bool = true,
    preInitialization: ((TestSourceKitLSPClient) -> Void)? = nil,
    cleanUp: (@Sendable () -> Void)? = nil,
    testName: String = #function
  ) async throws {
    var filesByPath: [RelativeFileLocation: String] = [:]
    for (fileLocation, contents) in files {
      let directories =
        switch fileLocation.directories.first {
        case "Sources", "Tests", "Plugins", "":
          fileLocation.directories
        case nil:
          ["Sources", "MyLibrary"]
        default:
          ["Sources"] + fileLocation.directories
        }

      filesByPath[RelativeFileLocation(directories: directories, fileLocation.fileName)] = contents
    }
    var manifest = manifest
    if !manifest.contains("swift-tools-version") {
      // Tests specify a shorthand package manifest that doesn't contain the tools version boilerplate.
      manifest = """
        // swift-tools-version: 5.10

        import PackageDescription

        \(manifest)
        """
    }
    filesByPath["Package.swift"] = manifest

    try await super.init(
      files: filesByPath,
      workspaces: workspaces,
      initializationOptions: initializationOptions,
      capabilities: capabilities,
      options: options,
      testHooks: testHooks,
      enableBackgroundIndexing: enableBackgroundIndexing,
      usePullDiagnostics: usePullDiagnostics,
      preInitialization: preInitialization,
      cleanUp: cleanUp,
      testName: testName
    )

    if pollIndex {
      // Wait for the indexstore-db to finish indexing
      try await testClient.send(PollIndexRequest())
    }
  }

  /// Build a SwiftPM package package manifest is located in the directory at `path`.
  package static func build(at path: URL, extraArguments: [String] = []) async throws {
    guard let swift = await ToolchainRegistry.forTesting.default?.swift else {
      throw Error.swiftNotFound
    }
    var arguments =
      [
        try swift.filePath,
        "build",
        "--package-path", try path.filePath,
        "--build-tests",
        "-Xswiftc", "-index-ignore-system-modules",
        "-Xcc", "-index-ignore-system-symbols",
      ] + extraArguments
    if let globalModuleCache = try globalModuleCache {
      arguments += [
        "-Xswiftc", "-module-cache-path", "-Xswiftc", try globalModuleCache.filePath,
      ]
    }
    try await Process.checkNonZeroExit(arguments: arguments)
  }

  /// Resolve package dependencies for the package at `path`.
  package static func resolvePackageDependencies(at path: URL) async throws {
    guard let swift = await ToolchainRegistry.forTesting.default?.swift else {
      throw Error.swiftNotFound
    }
    let arguments = [
      try swift.filePath,
      "package",
      "resolve",
      "--package-path", try path.filePath,
    ]
    try await Process.checkNonZeroExit(arguments: arguments)
  }
}
