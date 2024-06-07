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

import ArgumentParser
import Csourcekitd  // Not needed here, but fixes debugging...
import Diagnose
import Dispatch
import Foundation
import LSPLogging
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKCore
import SKSupport
import SourceKitLSP

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath
import var TSCBasic.localFileSystem

extension AbsolutePath {
  public init?(argument: String) {
    let path: AbsolutePath?

    if let cwd: AbsolutePath = localFileSystem.currentWorkingDirectory {
      path = try? AbsolutePath(validating: argument, relativeTo: cwd)
    } else {
      path = try? AbsolutePath(validating: argument)
    }

    guard let path = path else {
      return nil
    }

    self = path
  }

  public static var defaultCompletionKind: CompletionKind {
    // This type is most commonly used to select a directory, not a file.
    // Specify '.file()' in an argument declaration when necessary.
    .directory
  }
}
#if compiler(<5.11)
extension AbsolutePath: ExpressibleByArgument {}
#else
extension AbsolutePath: @retroactive ExpressibleByArgument {}
#endif

extension RelativePath {
  public init?(argument: String) {
    let path = try? RelativePath(validating: argument)

    guard let path = path else {
      return nil
    }

    self = path
  }
}
#if compiler(<5.11)
extension RelativePath: ExpressibleByArgument {}
#else
extension RelativePath: @retroactive ExpressibleByArgument {}
#endif

extension PathPrefixMapping {
  public init?(argument: String) {
    guard let eqIndex = argument.firstIndex(of: "=") else { return nil }
    self.init(
      original: String(argument[..<eqIndex]),
      replacement: String(argument[argument.index(after: eqIndex)...])
    )
  }
}
#if compiler(<5.11)
extension PathPrefixMapping: ExpressibleByArgument {}
#else
extension PathPrefixMapping: @retroactive ExpressibleByArgument {}
#endif

#if compiler(<5.11)
extension SKSupport.BuildConfiguration: ExpressibleByArgument {}
#else
extension SKSupport.BuildConfiguration: @retroactive ExpressibleByArgument {}
#endif

#if compiler(<5.11)
extension SKSupport.WorkspaceType: ExpressibleByArgument {}
#else
extension SKSupport.WorkspaceType: @retroactive ExpressibleByArgument {}
#endif

@main
struct SourceKitLSP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
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
  var buildConfiguration = BuildConfiguration.debug

  @Option(
    name: [.long, .customLong("build-path")],
    help: "Specify build/cache directory (--build-path option is deprecated, --scratch-path should be used instead)"
  )
  var scratchPath: AbsolutePath?

  @Option(
    name: .customLong("Xcc", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all C compiler invocations"
  )
  var buildFlagsCc = [String]()

  @Option(
    name: .customLong("Xcxx", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all C++ compiler invocations"
  )
  var buildFlagsCxx = [String]()

  @Option(
    name: .customLong("Xlinker", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all linker invocations"
  )
  var buildFlagsLinker = [String]()

  @Option(
    name: .customLong("Xswiftc", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass flag through to all Swift compiler invocations"
  )
  var buildFlagsSwift = [String]()

  @Option(
    name: .customLong("Xclangd", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Pass options to clangd command-line"
  )
  var clangdOptions = [String]()

  @Option(
    name: .customLong("index-store-path", withSingleDash: true),
    help: "Override index-store-path from the build system"
  )
  var indexStorePath: AbsolutePath?

  @Option(
    name: .customLong("index-db-path", withSingleDash: true),
    help: "Override index-database-path from the build system"
  )
  var indexDatabasePath: AbsolutePath?

  @Option(
    name: .customLong("index-prefix-map", withSingleDash: true),
    parsing: .unconditionalSingleValue,
    help: "Override the prefix map from the build system, values of form 'remote=local'"
  )
  var indexPrefixMappings = [PathPrefixMapping]()

  @Option(
    help: "Override default workspace type selection; one of 'swiftPM', 'compilationDatabase', or 'buildServer'"
  )
  var defaultWorkspaceType: SKSupport.WorkspaceType?

  @Option(
    name: .customLong("compilation-db-search-path"),
    parsing: .singleValue,
    help:
      "Specify a relative path where sourcekit-lsp should search for `compile_commands.json` or `compile_flags.txt` relative to the root of a workspace. Multiple search paths may be specified by repeating this option."
  )
  var compilationDatabaseSearchPaths = [RelativePath]()

  @Option(
    help: "Specify the directory where generated interfaces will be stored"
  )
  var generatedInterfacesPath = defaultDirectoryForGeneratedInterfaces

  @Option(
    help: "When server-side filtering is enabled, the maximum number of results to return"
  )
  var completionMaxResults = 200

  @Option(
    name: .customLong("experimental-feature"),
    help: """
      Enable an experimental sourcekit-lsp feature.
      Available features are: \(ExperimentalFeature.allCases.map(\.rawValue).joined(separator: ", "))
      """
  )
  var experimentalFeatures: [ExperimentalFeature] = []

  func mapOptions() -> SourceKitLSPServer.Options {
    var serverOptions = SourceKitLSPServer.Options()

    serverOptions.buildSetup.configuration = buildConfiguration
    serverOptions.buildSetup.defaultWorkspaceType = defaultWorkspaceType
    serverOptions.buildSetup.path = scratchPath
    serverOptions.buildSetup.flags.cCompilerFlags = buildFlagsCc
    serverOptions.buildSetup.flags.cxxCompilerFlags = buildFlagsCxx
    serverOptions.buildSetup.flags.linkerFlags = buildFlagsLinker
    serverOptions.buildSetup.flags.swiftCompilerFlags = buildFlagsSwift
    serverOptions.clangdOptions = clangdOptions
    serverOptions.compilationDatabaseSearchPaths = compilationDatabaseSearchPaths
    serverOptions.indexOptions.indexStorePath = indexStorePath
    serverOptions.indexOptions.indexDatabasePath = indexDatabasePath
    serverOptions.indexOptions.indexPrefixMappings = indexPrefixMappings
    serverOptions.completionOptions.maxResults = completionMaxResults
    serverOptions.generatedInterfacesPath = generatedInterfacesPath
    serverOptions.experimentalFeatures = Set(experimentalFeatures)

    return serverOptions
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

    let realStdoutHandle = FileHandle(fileDescriptor: realStdout, closeOnDealloc: false)

    // Directory should match the directory we are searching for logs in `DiagnoseCommand.addNonDarwinLogs`.
    let logFileDirectoryURL = URL(fileURLWithPath: ("~/.sourcekit-lsp/logs" as NSString).expandingTildeInPath)
    await setUpGlobalLogFileHandler(
      logFileDirectory: logFileDirectoryURL,
      logFileMaxBytes: 5_000_000,
      logRotateCount: 10
    )
    cleanOldLogFiles(logFileDirectory: logFileDirectoryURL, maxAge: 60 * 60 /* 1h */)

    let clientConnection = JSONRPCConnection(
      name: "client",
      protocol: MessageRegistry.lspProtocol,
      inFD: FileHandle.standardInput,
      outFD: realStdoutHandle
    )

    let installPath = try AbsolutePath(validating: Bundle.main.bundlePath)

    let server = SourceKitLSPServer(
      client: clientConnection,
      toolchainRegistry: ToolchainRegistry(installPath: installPath, localFileSystem),
      options: mapOptions(),
      onExit: {
        clientConnection.close()
      }
    )
    clientConnection.start(
      receiveHandler: server,
      closeHandler: {
        await server.prepareForExit()
        // FIXME: keep the FileHandle alive until we close the connection to
        // workaround SR-13822.
        withExtendedLifetime(realStdoutHandle) {}
        // Use _Exit to avoid running static destructors due to SR-12668.
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
