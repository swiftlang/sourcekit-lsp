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

import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import RegexBuilder
import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry
import XCTest

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv

// MARK: - Skip checks

/// Namespace for functions that are used to skip unsupported tests.
package actor SkipUnless {
  private enum FeatureCheckResult {
    case featureSupported
    case featureUnsupported(skipMessage: String)
  }

  private static let shared = SkipUnless()

  /// For any feature that has already been evaluated, the result of whether or not it should be skipped.
  private var checkCache: [String: FeatureCheckResult] = [:]

  /// Throw an `XCTSkip` if any of the following conditions hold
  ///  - The Swift version of the toolchain used for testing (`ToolchainRegistry.forTesting.default`) is older than
  ///    `swiftVersion`
  ///  - The Swift version of the toolchain used for testing is equal to `swiftVersion` and `featureCheck` returns
  ///    `false`. This is used for features that are introduced in `swiftVersion` but are not present in all toolchain
  ///    snapshots.
  ///
  /// Having the version check indicates when the check tests can be removed (namely when the minimum required version
  /// to test sourcekit-lsp is above `swiftVersion`) and it ensures that tests can’t stay in the skipped state over
  /// multiple releases.
  ///
  /// Independently of these checks, the tests are never skipped in Swift CI (identified by the presence of the `SWIFTCI_USE_LOCAL_DEPS` environment). Swift CI is assumed to always build its own toolchain, which is thus
  /// guaranteed to be up-to-date.
  private func skipUnlessSupportedByToolchain(
    swiftVersion: SwiftVersion,
    featureName: String = #function,
    file: StaticString,
    line: UInt,
    featureCheck: () async throws -> Bool
  ) async throws {
    return try await skipUnlessSupported(featureName: featureName, file: file, line: line) {
      let toolchainSwiftVersion = try await unwrap(ToolchainRegistry.forTesting.default).swiftVersion
      let requiredSwiftVersion = SwiftVersion(swiftVersion.major, swiftVersion.minor)
      if toolchainSwiftVersion < requiredSwiftVersion {
        return .featureUnsupported(
          skipMessage: """
            Skipping because toolchain has Swift version \(toolchainSwiftVersion) \
            but test requires at least \(requiredSwiftVersion)
            """
        )
      } else if toolchainSwiftVersion == requiredSwiftVersion {
        logger.info("Checking if feature '\(featureName)' is supported")
        defer {
          logger.info("Done checking if feature '\(featureName)' is supported")
        }
        if try await !featureCheck() {
          return .featureUnsupported(skipMessage: "Skipping because toolchain doesn't contain \(featureName)")
        } else {
          return .featureSupported
        }
      } else {
        return .featureSupported
      }
    }
  }

  private func skipUnlessSupported(
    allowSkippingInCI: Bool = false,
    featureName: String = #function,
    file: StaticString,
    line: UInt,
    featureCheck: () async throws -> FeatureCheckResult
  ) async throws {
    let checkResult: FeatureCheckResult
    if let cachedResult = checkCache[featureName] {
      checkResult = cachedResult
    } else if ProcessEnv.block["SWIFTCI_USE_LOCAL_DEPS"] != nil && !allowSkippingInCI {
      // In general, don't skip tests in CI. Toolchain should be up-to-date
      checkResult = .featureSupported
    } else {
      checkResult = try await featureCheck()
    }
    checkCache[featureName] = checkResult

    if case .featureUnsupported(let skipMessage) = checkResult {
      throw XCTSkip(skipMessage, file: file, line: line)
    }
  }

  /// A long test is a test that takes longer than 1-2s to execute.
  package static func longTestsEnabled() throws {
    if let value = ProcessInfo.processInfo.environment["SKIP_LONG_TESTS"], value == "1" || value == "YES" {
      throw XCTSkip("Long tests disabled using the `SKIP_LONG_TESTS` environment variable")
    }
  }

  package static func platformIsDarwin(_ message: String) throws {
    try XCTSkipUnless(Platform.current == .darwin, message)
  }

  package static func platformIsWindows(_ message: String) throws {
    try XCTSkipUnless(Platform.current == .windows, message)
  }

  package static func platformSupportsTaskPriorityElevation() throws {
    #if os(macOS)
    guard #available(macOS 14.0, *) else {
      // Priority elevation was implemented by https://github.com/apple/swift/pull/63019, which is available in the
      // Swift 5.9 runtime included in macOS 14.0+
      throw XCTSkip("Priority elevation of tasks is only supported on macOS 14 and above")
    }
    #endif
  }

  /// Check if we can use the build artifacts in the sourcekit-lsp build directory to build a macro package without
  /// re-building swift-syntax.
  package static func canBuildMacroUsingSwiftSyntaxFromSourceKitLSPBuild(
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    try XCTSkipUnless(
      Platform.current != .windows,
      "Temporarily skipping as we need to fix these tests to use the cmake-built swift-syntax libraries on Windows."
    )

    return try await shared.skipUnlessSupported(file: file, line: line) {
      do {
        let project = try await SwiftPMTestProject(
          files: [
            "MyMacros/MyMacros.swift": #"""
            import SwiftParser

            func test() {
              _ = Parser.parse(source: "let a")
            }
            """#,
            "MyMacroClient/MyMacroClient.swift": """
            """,
          ],
          manifest: SwiftPMTestProject.macroPackageManifest
        )
        try await SwiftPMTestProject.build(
          at: project.scratchDirectory,
          extraArguments: ["--experimental-prepare-for-indexing"]
        )
        return .featureSupported
      } catch {
        return .featureUnsupported(
          skipMessage: """
            Skipping because macro could not be built using build artifacts in the sourcekit-lsp build directory. \
            This usually happens if sourcekit-lsp was built using a different toolchain than the one used at test-time.

            Reason:
            \(error)
            """
        )
      }
    }
  }

  package static func canSwiftPMCompileForIOS(
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    return try await shared.skipUnlessSupported(allowSkippingInCI: true, file: file, line: line) {
      #if os(macOS)
      let project = try await SwiftPMTestProject(files: [
        "MyFile.swift": """
        public func foo() {}
        """
      ])
      do {
        try await SwiftPMTestProject.build(
          at: project.scratchDirectory,
          extraArguments: [
            "--swift-sdk", "arm64-apple-ios",
          ]
        )
        return .featureSupported
      } catch {
        return .featureUnsupported(skipMessage: "Cannot build for iOS: \(error)")
      }
      #else
      return .featureUnsupported(skipMessage: "Cannot build for iOS outside macOS by default")
      #endif
    }
  }

  package static func canCompileForWasm(
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    return try await shared.skipUnlessSupported(allowSkippingInCI: true, file: file, line: line) {
      let swiftFrontend = try await unwrap(ToolchainRegistry.forTesting.default?.swift).deletingLastPathComponent()
        .appendingPathComponent("swift-frontend")
      return try await withTestScratchDir { scratchDirectory in
        let input = scratchDirectory.appendingPathComponent("Input.swift")
        guard FileManager.default.createFile(atPath: input.path, contents: nil) else {
          throw GenericError("Failed to create input file")
        }
        // If we can't compile for wasm, this fails complaining that it can't find the stdlib for wasm.
        let result = try await withTimeout(defaultTimeoutDuration) {
          try await Process.run(
            arguments: [
              try swiftFrontend.filePath,
              "-typecheck",
              try input.filePath,
              "-triple",
              "wasm32-unknown-none-wasm",
              "-enable-experimental-feature",
              "Embedded",
              "-Xcc",
              "-fdeclspec",
            ],
            workingDirectory: nil
          )
        }
        if result.exitStatus == .terminated(code: 0) {
          return .featureSupported
        }
        return .featureUnsupported(skipMessage: "Skipping because toolchain can not compile for wasm")
      }
    }
  }

  package static func sourcekitdSupportsPlugin(
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    return try await shared.skipUnlessSupportedByToolchain(swiftVersion: SwiftVersion(6, 2), file: file, line: line) {
      guard let sourcekitdPath = await ToolchainRegistry.forTesting.default?.sourcekitd else {
        throw GenericError("Could not find SourceKitD")
      }
      let sourcekitd = try await SourceKitD.getOrCreate(
        dylibPath: sourcekitdPath,
        pluginPaths: try sourceKitPluginPaths
      )
      do {
        let response = try await sourcekitd.send(
          sourcekitd.dictionary([
            sourcekitd.keys.request: sourcekitd.requests.codeCompleteSetPopularAPI,
            sourcekitd.keys.codeCompleteOptions: [
              sourcekitd.keys.useNewAPI: 1
            ],
          ]),
          timeout: defaultTimeoutDuration,
          fileContents: nil
        )
        return response[sourcekitd.keys.useNewAPI] == 1
      } catch {
        return false
      }
    }
  }

  package static func canLoadPluginsBuiltByToolchain(
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    return try await shared.skipUnlessSupported(file: file, line: line) {
      let project = try await SwiftPMTestProject(
        files: [
          "Plugins/plugin.swift": #"""
          import Foundation
          import PackagePlugin
          @main struct CodeGeneratorPlugin: BuildToolPlugin {
            func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
              let genSourcesDir = context.pluginWorkDirectoryURL.appending(path: "GeneratedSources")
              guard let target = target as? SourceModuleTarget else { return [] }
              let codeGenerator = try context.tool(named: "CodeGenerator").url
              let generatedFile = genSourcesDir.appending(path: "\(target.name)-generated.swift")
              return [.buildCommand(
                displayName: "Generating code for \(target.name)",
                executable: codeGenerator,
                arguments: [
                  generatedFile.path
                ],
                inputFiles: [],
                outputFiles: [generatedFile]
              )]
            }
          }
          """#,

          "Sources/CodeGenerator/CodeGenerator.swift": #"""
          import Foundation
          try "let foo = 1".write(
            to: URL(fileURLWithPath: CommandLine.arguments[1]),
            atomically: true,
            encoding: String.Encoding.utf8
          )
          """#,

          "Sources/TestLib/TestLib.swift": #"""
          func useGenerated() {
            _ = 1️⃣foo
          }
          """#,
        ],
        manifest: """
          // swift-tools-version: 6.0
          import PackageDescription
          let package = Package(
            name: "PluginTest",
            targets: [
              .executableTarget(name: "CodeGenerator"),
              .target(
                name: "TestLib",
                plugins: [.plugin(name: "CodeGeneratorPlugin")]
              ),
              .plugin(
                name: "CodeGeneratorPlugin",
                capability: .buildTool(),
                dependencies: ["CodeGenerator"]
              ),
            ]
          )
          """,
        enableBackgroundIndexing: true
      )

      let (uri, positions) = try project.openDocument("TestLib.swift")

      let result = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )

      if result?.locations?.only == nil {
        return .featureUnsupported(skipMessage: "Skipping because plugin protocols do not match.")
      }
      return .featureSupported
    }
  }
}

// MARK: - Parsing Swift compiler version

fileprivate extension String {
  init?(bytes: [UInt8], encoding: Encoding) {
    self = bytes.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return ""
      }
      let data = Data(bytes: baseAddress, count: buffer.count)
      return String(data: data, encoding: encoding)!
    }
  }
}

private struct GenericError: Error, CustomStringConvertible {
  var description: String

  init(_ message: String) {
    self.description = message
  }
}
