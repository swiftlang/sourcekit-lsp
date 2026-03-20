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

package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
import TSCBasic
package import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

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
  ///  - A macro target named `MyMacros`
  ///  - And executable target named `MyMacroClient`
  ///
  /// The macro target is a minimal executable that implements the macro plugin protocol directly without depending on
  /// SwiftSyntax. Use `minimalMacroPluginSource(expansions:)` to generate the source for the `MyMacros` target.
  package static let minimalMacroPackageManifest: String = """
    // swift-tools-version: 5.10

    import PackageDescription
    import CompilerPluginSupport

    let package = Package(
      name: "MyMacro",
      platforms: [.macOS(.v11)],
      targets: [
        .macro(name: "MyMacros"),
        .executableTarget(name: "MyMacroClient", dependencies: ["MyMacros"]),
      ]
    )
    """

  package struct HardcodedMacroExpansion {
    package var typeName: String
    package var role: String
    package var expandedSource: String

    package init(typeName: String, role: String, expandedSource: String) {
      self.typeName = typeName
      self.role = role
      self.expandedSource = expandedSource
    }
  }

  /// Generate the source for a minimal macro plugin that returns hardcoded expansions based on type name and macro role.
  package static func minimalMacroPluginSource(expansions: [HardcodedMacroExpansion]) -> String {
    let expansionsList =
      expansions
      .map { expansion in
        "(typeName: \"\(expansion.typeName)\", role: \"\(expansion.role)\", expandedSource: \"\(expansion.expandedSource)\"),"
      }
      .joined(separator: "\n    ")

    return """
      import Foundation

      private let expansions: [(typeName: String, role: String, expandedSource: String)] = [
          \(expansionsList)
      ]

      private struct MacroInfo: Decodable { 
        let typeName: String
      }
      private struct GetCapabilityRequest: Decodable {}
      private struct ExpandRequest: Decodable {
        let macro: MacroInfo
        let macroRole: String?
      }
      private struct IncomingMessage: Decodable {
        let getCapability: GetCapabilityRequest?
        let expandFreestandingMacro: ExpandRequest?
        let expandAttachedMacro: ExpandRequest?
      }
      private struct GetCapabilityResponse: Encodable {
        struct Result: Encodable {
          struct Capability: Encodable { let protocolVersion = 7 }
          let capability = Capability()
        }
        let getCapabilityResult = Result()
      }
      private struct ExpandMacroResponse: Encodable {
        struct Result: Encodable {
          let expandedSource: String
          let diagnostics: [String] = []
        }
        let expandMacroResult: Result
      }

      @main
      struct MacroPlugin {
        static func main() throws {
          while true {
            guard let headerData = try read(count: 8), headerData.count == 8 else {
              break
            }
            let payloadLength = headerData.withUnsafeBytes { buffer in
              UInt64(littleEndian: buffer.load(as: UInt64.self))
            }
            if payloadLength == 0 { break }
            guard let payloadData = try read(count: Int(payloadLength)),
                  payloadData.count == Int(payloadLength) else {
              break
            }
            guard let message = try? JSONDecoder().decode(IncomingMessage.self, from: payloadData) else {
              continue
            }
            if message.getCapability != nil {
              try writeMessage(try JSONEncoder().encode(GetCapabilityResponse()))
            } else if let expand = message.expandFreestandingMacro ?? message.expandAttachedMacro {
              let expandedSource = expansions.first {
                $0.typeName == expand.macro.typeName && $0.role == (expand.macroRole ?? "")
              }?.expandedSource ?? ""
              try writeMessage(try JSONEncoder().encode(
                ExpandMacroResponse(expandMacroResult: .init(expandedSource: expandedSource))
              ))
            }
          }
        }
      }

      private func read(count: Int) throws -> Data? {
        var accumulated = Data()
        while accumulated.count < count {
          let remaining = count - accumulated.count
          guard let chunk = try FileHandle.standardInput.read(upToCount: remaining), !chunk.isEmpty else {
            return accumulated.isEmpty ? nil : accumulated
          }
          accumulated.append(chunk)
        }
        return accumulated
      }

      private func writeMessage(_ data: Data) throws {
        var length = UInt64(data.count).littleEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        try FileHandle.standardOutput.write(contentsOf: header)
        try FileHandle.standardOutput.write(contentsOf: data)
      }
      """
  }

  /// Create a new SwiftPM package with the given files.
  ///
  /// If `index` is `true`, then the package will be built, indexing all modules within the package.
  package init(
    files: [RelativeFileLocation: String],
    manifest: String = SwiftPMTestProject.defaultPackageManifest,
    workspaces: (_ scratchDirectory: URL) async throws -> [WorkspaceFolder] = {
      [WorkspaceFolder(uri: DocumentURI($0))]
    },
    initializationOptions: LSPAny? = nil,
    capabilities: ClientCapabilities = ClientCapabilities(),
    options: SourceKitLSPOptions? = nil,
    toolchainRegistry: ToolchainRegistry = .forTesting,
    hooks: Hooks = Hooks(),
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
      toolchainRegistry: toolchainRegistry,
      hooks: hooks,
      enableBackgroundIndexing: enableBackgroundIndexing,
      usePullDiagnostics: usePullDiagnostics,
      preInitialization: preInitialization,
      cleanUp: cleanUp,
      testName: testName
    )

    if pollIndex {
      // Wait for the indexstore-db to finish indexing
      try await testClient.send(SynchronizeRequest(index: true))
    }
  }

  /// Build a SwiftPM package package manifest is located in the directory at `path`.
  package static func build(
    at path: URL,
    buildSystem: SwiftPMBuildSystem = .native,
    extraArguments: [String] = []
  ) async throws {
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
        "--build-system", buildSystem.rawValue,
      ] + extraArguments
    if let globalModuleCache = try globalModuleCache {
      arguments += [
        "-Xswiftc", "-module-cache-path", "-Xswiftc", try globalModuleCache.filePath,
      ]
    }
    let argumentsCopy = arguments
    let output = try await withTimeout(defaultTimeoutDuration) {
      try await Process.checkNonZeroExit(arguments: argumentsCopy)
    }
    logger.debug(
      """
      'swift build' output:
      \(output)
      """
    )
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
    let output = try await withTimeout(defaultTimeoutDuration) {
      try await Process.checkNonZeroExit(arguments: arguments)
    }
    logger.debug(
      """
      'swift package resolve' output:
      \(output)
      """
    )
  }
}
