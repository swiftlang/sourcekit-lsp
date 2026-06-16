//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
@_spi(SourceKitLSP) package import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) package import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
import Synchronization
import TSCExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import struct TSCBasic.ProcessResult
import enum TSCBasic.SystemError

private let updateSymbolGraphIDForLogging = Atomic<UInt32>(1)

package struct UpdateSymbolGraphTaskDescription: IndexTaskDescription {
  package static let idPrefix = "update-symbolgraph"
  package let id = updateSymbolGraphIDForLogging.wrappingAdd(1, ordering: .relaxed).oldValue

  /// The files in the target.
  package let filesToIndex: [FileAndOutputPath]

  /// The target in whose context the symbol graph should be generated.
  package let target: BuildTargetIdentifier

  /// The common language of all main files.
  package let language: Language

  /// The build server manager that is used to get the toolchain and build settings.
  private let buildServerManager: BuildServerManager

  private let logMessageToIndexLog:
    @Sendable (
      _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
    ) -> Void

  /// How long to wait until we cancel an update symbolgraph task.
  private let timeout: Duration

  package var isIdempotent: Bool { true }

  package var estimatedCPUCoreCount: Int { 1 }

  package var dependencies: [TaskDependencyAction<UpdateSymbolGraphTaskDescription>] {
    return []
  }

  package func dependencies(
    to queuedTasks: [UpdateSymbolGraphTaskDescription]
  ) -> [TaskDependencyAction<UpdateSymbolGraphTaskDescription>] {
    return []
  }

  package var description: String {
    return self.redactedDescription
  }

  package var redactedDescription: String {
    return "update-symbolgraph-\(id)"
  }

  init(
    filesToIndex: [FileAndOutputPath],
    target: BuildTargetIdentifier,
    language: Language,
    buildServerManager: BuildServerManager,
    logMessageToIndexLog:
      @escaping @Sendable (
        _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
      ) -> Void,
    timeout: Duration
  ) {
    self.filesToIndex = filesToIndex
    self.target = target
    self.language = language
    self.buildServerManager = buildServerManager
    self.logMessageToIndexLog = logMessageToIndexLog
    self.timeout = timeout
  }

  package func execute() async {
    await withLoggingSubsystemAndScope(subsystem: indexLoggingSubsystem, scope: "update-symbolgraph-\(id % 100)") {
      guard language == .swift else { return }

      let buildSettings: FileBuildSettings
      let swiftc: URL

      do {
        guard let firstFile = filesToIndex.first?.file.mainFile else { return }
        guard
          let resolvedSettings = await buildServerManager.buildSettings(
            for: firstFile,
            in: target,
            language: language,
            fallbackAfterTimeout: true
          )
        else { return }
        buildSettings = resolvedSettings

        guard let toolchain = await buildServerManager.toolchain(for: target, language: language) else { return }
        guard let resolvedSwiftc = toolchain.swiftc else { return }
        swiftc = resolvedSwiftc
      }

      // --- Directory setup ---
      let baseDir: AbsolutePath
      if let workingDirectory = buildSettings.workingDirectory,
        let parsedPath = try? AbsolutePath(validating: workingDirectory)
      {
        baseDir = parsedPath
      } else if let fallbackPath = try? AbsolutePath(validating: FileManager.default.currentDirectoryPath) {
        baseDir = fallbackPath
      } else {
        return
      }

      let buildDir = baseDir.appending(component: ".build")
      let symbolGraphDir = buildDir.appending(component: "symbol-graphs")
      let customModulesDir = symbolGraphDir.appending(component: "Modules")

      try? FileManager.default.createDirectory(
        atPath: customModulesDir.pathString,
        withIntermediateDirectories: true
      )

      // --- Parse module name and build base args ---
      let rawArgs = buildSettings.compilerArguments

      var moduleName = "Target"
      if let idx = rawArgs.firstIndex(of: "-module-name"), idx + 1 < rawArgs.count {
        moduleName = rawArgs[idx + 1]
      }

      let moduleOutputPath = customModulesDir.appending(component: "\(moduleName).swiftmodule").pathString
      try? FileManager.default.removeItem(atPath: moduleOutputPath)

      var baseArgs: [String] = ["-I", customModulesDir.pathString]

      baseArgs += ["-module-name", moduleName]

      var i = 0
      while i < rawArgs.count {
        let arg = rawArgs[i]

        if arg == "-I" || arg == "-F" || arg == "-target" || arg == "-sdk"
          || arg == "-swift-version" || arg == "-package-name" || arg == "-resource-dir" || arg == "-Xcc"
          || arg == "-module-cache-path" || arg == "-enable-upcoming-feature" || arg == "-Xfrontend"
        {
          if i + 1 < rawArgs.count {
            baseArgs.append(arg)
            var next = rawArgs[i + 1]
            if next.contains("vscode-local:") {
              next = next.replacingOccurrences(of: "vscode-local:", with: "file:")
            }
            baseArgs.append(next)
            i += 2
          } else {
            i += 1
          }
          continue
        }

        if arg.hasSuffix(".swift") {
          baseArgs.append(arg)
          i += 1
          continue
        }

        if arg.hasPrefix("-D") {
          baseArgs.append(arg)
          i += 1
          continue
        }

        i += 1
      }

      if !baseArgs.contains("-wmo") && !baseArgs.contains("-whole-module-optimization") {
        baseArgs.append("-wmo")
      }

      // --- Clean environment ---
      var cleanEnvironment = ProcessInfo.processInfo.environment
      cleanEnvironment.removeValue(forKey: "SWIFT_DRIVER_SUPPLEMENTARY_OUTPUT_FILE_MAP")
      cleanEnvironment.removeValue(forKey: "SWIFT_DRIVER_OUTPUT_FILE_MAP")
      cleanEnvironment.removeValue(forKey: "SWIFT_DRIVER_TEMP_DIR")
      cleanEnvironment.removeValue(forKey: "SWIFT_DRIVER_RESPONSE_FILE_PATH")
      cleanEnvironment.removeValue(forKey: "SWIFT_DRIVER_TOOLNAME")

      let taskId = "symbol-graph-\(id)"

      logMessageToIndexLog(
        "Updating symbol graph for target: \(target.uri.stringValue)",
        .info,
        .begin(StructuredLogBegin(title: "Symbol Graph Run", taskID: taskId))
      )

      // emit module and symbol graph
      let args =
        [swiftc.path] + baseArgs + [
          "-emit-module",
          "-emit-module-path", moduleOutputPath,
          "-Xfrontend", "-emit-symbol-graph",
          "-Xfrontend", "-emit-symbol-graph-dir", "-Xfrontend", symbolGraphDir.pathString,
          "-Xfrontend", "-experimental-skip-all-function-bodies",
        ]
      let commandString = args.joined(separator: " ")
      do {
        let process = Process(
          arguments: args,
          environment: cleanEnvironment,
          workingDirectory: baseDir,
          outputRedirection: .none
        )

        try process.launch()

        let result = try await process.waitUntilExit()
        let exitStatus = result.exitStatus.exhaustivelySwitchable

        if exitStatus.isSuccess {
          logMessageToIndexLog(
            """
            Symbol graph generation completed successfully.
            Module path: \(moduleOutputPath)
            Symbol graph directory: \(symbolGraphDir.pathString)
            Exit status: \(exitStatus.description),
            Args: \(commandString)
            """,
            .info,
            .end(StructuredLogEnd(taskID: taskId))
          )
        } else {
          let stderrOutput = (try? result.utf8stderrOutput()) ?? "No stderr output"
          let stdoutOutput = (try? result.utf8Output()) ?? "No stdout output"

          logMessageToIndexLog(
            """
            Symbol graph generation failed.
            Exit status: \(exitStatus.description)

            STDERR:
            \(stderrOutput)

            STDOUT:
            \(stdoutOutput)
            """,
            .error,
            .end(StructuredLogEnd(taskID: taskId))
          )
        }
      } catch {
        logMessageToIndexLog(
          """
          Failed to launch symbol graph extraction process.
          Error: \(error.localizedDescription)
          Working directory: \(baseDir.pathString)
          """,
          .error,
          .end(StructuredLogEnd(taskID: taskId))
        )
      }
    }
  }
}
