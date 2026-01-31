//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public import ArgumentParser
import BuildServerIntegration
import Csourcekitd  // Not needed here, but fixes debugging...
import Diagnose
import Dispatch
import Foundation
import InProcessClient
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath

#if canImport(Android)
import Android
#endif

struct PathPrefixMapping: ArgumentParser.ExpressibleByArgument {
  /// Path prefix to be replaced, typically the canonical or hermetic path.
  package let original: String

  /// Replacement path prefix, typically the path on the local machine.
  package let replacement: String

  init?(argument: String) {
    guard let eqIndex = argument.firstIndex(of: "=") else { return nil }
    self.original = String(argument[..<eqIndex])
    self.replacement = String(argument[argument.index(after: eqIndex)...])
  }
}

extension SKOptions.BuildConfiguration: ArgumentParser.ExpressibleByArgument {}

extension SKOptions.WorkspaceType: ArgumentParser.ExpressibleByArgument {}

@main
struct SourceKitLSP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sourcekit-lsp",
    abstract: "Language Server Protocol implementation for Swift and C-based languages",
    subcommands: [
      DiagnoseCommand.self,
      DebugCommand.self,
    ]
  )

  @Option(
    name: [.customLong("configuration")],
    help: "Build with configuration [debug|release]"
  )
  var buildConfiguration: BuildConfiguration?

  @Option(
    name: [.long, .customLong("build-path")],
    help: "Specify build/cache directory (--build-path option is deprecated, --scratch-path should be used instead)"
  )
  var scratchPath: String?

  @Option(
    name: .customLong("Xcc", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all C compiler invocations"
  )
  var buildFlagsCc: [String] = []

  @Option(
    name: .customLong("Xcxx", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all C++ compiler invocations"
  )
  var buildFlagsCxx: [String] = []

  @Option(
    name: .customLong("Xlinker", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all linker invocations"
  )
  var buildFlagsLinker: [String] = []

  @Option(
    name: .customLong("Xswiftc", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all Swift compiler invocations"
  )
  var buildFlagsSwift: [String] = []

  @Option(
    name: .customLong("Xclangd", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass options to clangd command-line"
  )
  var clangdOptions: [String] = []

  @Option(
    name: .customLong("index-prefix-map", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Override the prefix map from the build system, values of form 'remote=local'"
  )
  var indexPrefixMappings: [PathPrefixMapping] = []

  @Option(
    help: "Override default workspace type selection; one of 'swiftPM', 'compilationDatabase', or 'buildServer'"
  )
  var defaultWorkspaceType: SKOptions.WorkspaceType?

  @Option(
    name: .customLong("compilation-db-search-path"),
    parsing: .singleValue,
    help:
      "Specify a relative path where sourcekit-lsp should search for `compile_commands.json` or `compile_flags.txt` relative to the root of a workspace. Multiple search paths may be specified by repeating this option."
  )
  var compilationDatabaseSearchPaths: [String] = []

  @Option(
    help: "Specify the directory where generated files will be stored"
  )
  var generatedFilesPath: String? = nil

  @Option(
    name: .customLong("experimental-feature"),
    help: """
      Enable an experimental sourcekit-lsp feature.
      Available features are: \(ExperimentalFeature.allNonInternalCases.map(\.rawValue).joined(separator: ", "))
      """
  )
  var experimentalFeatures: [String] = []

  /// Maps The options passed on the command line to a `SourceKitLSPOptions` struct.
  func commandLineOptions() -> SourceKitLSPOptions {
    return SourceKitLSPOptions(
      swiftPM: SourceKitLSPOptions.SwiftPMOptions(
        configuration: buildConfiguration,
        scratchPath: scratchPath,
        cCompilerFlags: buildFlagsCc.nilIfEmpty,
        cxxCompilerFlags: buildFlagsCxx.nilIfEmpty,
        swiftCompilerFlags: buildFlagsSwift.nilIfEmpty,
        linkerFlags: buildFlagsLinker.nilIfEmpty
      ),
      fallbackBuildSystem: SourceKitLSPOptions.FallbackBuildSystemOptions(
        cCompilerFlags: buildFlagsCc.nilIfEmpty,
        cxxCompilerFlags: buildFlagsCxx.nilIfEmpty,
        swiftCompilerFlags: buildFlagsSwift.nilIfEmpty
      ),
      compilationDatabase: SourceKitLSPOptions.CompilationDatabaseOptions(
        searchPaths: compilationDatabaseSearchPaths.nilIfEmpty
      ),
      clangdOptions: clangdOptions,
      index: SourceKitLSPOptions.IndexOptions(
        indexPrefixMap: [String: String](
          indexPrefixMappings.map { ($0.original, $0.replacement) },
          uniquingKeysWith: { lhs, rhs in rhs }
        ).nilIfEmpty
      ),
      defaultWorkspaceType: defaultWorkspaceType,
      generatedFilesPath: generatedFilesPath,
      experimentalFeatures: Set(experimentalFeatures.compactMap(ExperimentalFeature.init)).nilIfEmpty
    )
  }

  var globalConfigurationOptions: SourceKitLSPOptions {
    var options = SourceKitLSPOptions.merging(
      base: commandLineOptions(),
      override: SourceKitLSPOptions(
        path: FileManager.default.homeDirectoryForCurrentUser
          .appending(components: ".sourcekit-lsp", "config.json")
      )
    )
    if Platform.current == .darwin {
      for applicationSupportDir in FileManager.default.urls(for: .applicationSupportDirectory, in: [.allDomainsMask]) {
        options = SourceKitLSPOptions.merging(
          base: options,
          override: SourceKitLSPOptions(
            path:
              applicationSupportDir
              .appending(components: "org.swift.sourcekit-lsp", "config.json")
          )
        )
      }
    }
    if let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
      options = SourceKitLSPOptions.merging(
        base: options,
        override: SourceKitLSPOptions(
          path:
            URL(fileURLWithPath: xdgConfigHome)
            .appending(components: "sourcekit-lsp", "config.json")
        )
      )
    }
    return options
  }

  /// Create a new file that can be used to use as an input or output mirror file and return a file handle that can be
  /// used to write to that file.
  private func createMirrorFile(in directory: URL) throws -> FileHandle {
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.timeZone = NSTimeZone.local
    let date = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

    let inputMirrorURL = directory.appending(component: "\(date).log")

    logger.log("Mirroring input to \(inputMirrorURL)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.createFile(at: inputMirrorURL, contents: nil)

    return try FileHandle(forWritingTo: inputMirrorURL)
  }

  func run() async throws {
    // Dup stdout and redirect the fd to stderr so that a careless print()
    // will not break our connection stream.
    let realStdout = dup(STDOUT_FILENO)
    if realStdout == -1 {
      fatalError("failed to dup stdout: \(strerror(errno)!)")
    }
    if dup2(STDERR_FILENO, STDOUT_FILENO) == -1 {
      fatalError("failed to redirect stdout -> stderr: \(strerror(errno)!)")
    }

    LoggingScope.configureDefaultLoggingSubsystem("org.swift.sourcekit-lsp")

    logger.log("sourcekit-lsp launched from \(ProcessInfo.processInfo.arguments.first ?? "<nil>")")

    let globalConfigurationOptions = globalConfigurationOptions
    if let logLevelStr = globalConfigurationOptions.loggingOrDefault.level,
      let logLevel = NonDarwinLogLevel(logLevelStr)
    {
      LogConfig.logLevel = logLevel
    }
    if let privacyLevelStr = globalConfigurationOptions.loggingOrDefault.privacyLevel,
      let privacyLevel = NonDarwinLogPrivacy(privacyLevelStr)
    {
      LogConfig.privacyLevel = privacyLevel
    }

    let realStdoutHandle = FileHandle(fileDescriptor: realStdout, closeOnDealloc: false)

    // Directory should match the directory we are searching for logs in `DiagnoseCommand.addNonDarwinLogs`.
    let logFileDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
      .appending(components: ".sourcekit-lsp", "logs")
    await setUpGlobalLogFileHandler(
      logFileDirectory: logFileDirectoryURL,
      logFileMaxBytes: 5_000_000,
      logRotateCount: 10
    )
    cleanOldLogFiles(logFileDirectory: logFileDirectoryURL, maxAge: 60 * 60 /* 1h */)

    let inputMirror = orLog("Setting up input mirror") {
      if let inputMirrorDirectory = globalConfigurationOptions.loggingOrDefault.inputMirrorDirectory {
        return try createMirrorFile(in: URL(fileURLWithPath: inputMirrorDirectory))
      }
      return nil
    }

    let outputMirror = orLog("Setting up output mirror") {
      if let outputMirrorDirectory = globalConfigurationOptions.loggingOrDefault.outputMirrorDirectory {
        return try createMirrorFile(in: URL(fileURLWithPath: outputMirrorDirectory))
      }
      return nil
    }

    let clientConnection = JSONRPCConnection(
      name: "client",
      protocol: MessageRegistry.lspProtocol,
      receiveFD: FileHandle.standardInput,
      sendFD: realStdoutHandle,
      receiveMirrorFile: inputMirror,
      sendMirrorFile: outputMirror
    )

    // For reasons that are completely oblivious to me, `DispatchIO.write`, which is used to write LSP responses to
    // stdout fails with error code 5 on Windows unless we call `AbsolutePath(validating:)` on some URL first.
    _ = try AbsolutePath(validating: Bundle.main.bundlePath)

    let server = SourceKitLSPServer(
      client: clientConnection,
      toolchainRegistry: ToolchainRegistry(installPath: Bundle.main.bundleURL),
      languageServerRegistry: .staticallyKnownServices,
      options: globalConfigurationOptions,
      hooks: Hooks(),
      onExit: {
        clientConnection.close()
      }
    )
    clientConnection.start(
      receiveHandler: server,
      closeHandler: {
        await server.prepareForExit()
        // Use _Exit to avoid running static destructors due to https://github.com/swiftlang/swift/issues/55112.
        _Exit(0)
      }
    )

    // Park the main function by sleeping for 10 years.
    // All request handling is done on other threads and sourcekit-lsp exits by calling `_Exit` when it receives a
    // shutdown notification.
    while true {
      try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
      logger.fault("10 year wait that's parking the main thread expired. Waiting again.")
    }
  }
}

private extension Collection {
  var nilIfEmpty: Self? {
    if self.isEmpty {
      return nil
    }
    return self
  }
}
