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
import Csourcekitd // Not needed here, but fixes debugging...
import Dispatch
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import LSPLogging
import SKCore
import SKSupport
import SourceKitLSP

import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem

extension AbsolutePath: ExpressibleByArgument {
  public init?(argument: String) {
    if let cwd = localFileSystem.currentWorkingDirectory {
      self.init(argument, relativeTo: cwd)
    } else {
      guard let path = try? AbsolutePath(validating: argument) else {
        return nil
      }
      self = path
    }
  }

  public static var defaultCompletionKind: CompletionKind {
    // This type is most commonly used to select a directory, not a file.
    // Specify '.file()' in an argument declaration when necessary.
    .directory
  }
}

extension PathPrefixMapping: ExpressibleByArgument {
  public init?(argument: String) {
    guard let eqIndex = argument.firstIndex(of: "=") else { return nil }
    self.init(original: String(argument[..<eqIndex]),
              replacement: String(argument[argument.index(after: eqIndex)...]))
  }
}

extension LogLevel: ExpressibleByArgument {}
extension BuildConfiguration: ExpressibleByArgument {}

struct Main: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Language Server Protocol implementation for Swift and C-based languages"
  )

  /// Whether to wait for a response before handling the next request.
  /// Used for testing.
  @Flag(name: .customLong("sync"))
  var syncRequests = false

  @Option(help: "Set the logging level [debug|info|warning|error] (default: \(LogLevel.default))")
  var logLevel: LogLevel?

  @Option(
    name: [.customLong("configuration"), .customShort("c")],
    help: "Build with configuration [debug|release]"
  )
  var buildConfiguration = BuildConfiguration.debug

  @Option(name: [.long, .customLong("build-path")], help: "Specify build/cache directory (--build-path option is deprecated, --scratch-path should be used instead)")
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
    help: "Specify the directory where generated interfaces will be stored"
  )
  var generatedInterfacesPath = defaultDirectoryForGeneratedInterfaces

  @Option(
    help: "Whether to enable server-side filtering in code-completion"
  )
  var completionServerSideFiltering = true

  @Option(
    help: "When server-side filtering is enabled, the maximum number of results to return"
  )
  var completionMaxResults = 200

  func mapOptions() -> SourceKitServer.Options {
    var serverOptions = SourceKitServer.Options()

    serverOptions.buildSetup.configuration = buildConfiguration
    serverOptions.buildSetup.path = scratchPath
    serverOptions.buildSetup.flags.cCompilerFlags = buildFlagsCc
    serverOptions.buildSetup.flags.cxxCompilerFlags = buildFlagsCxx
    serverOptions.buildSetup.flags.linkerFlags = buildFlagsLinker
    serverOptions.buildSetup.flags.swiftCompilerFlags = buildFlagsSwift
    serverOptions.clangdOptions = clangdOptions
    serverOptions.indexOptions.indexStorePath = indexStorePath
    serverOptions.indexOptions.indexDatabasePath = indexDatabasePath
    serverOptions.indexOptions.indexPrefixMappings = indexPrefixMappings
    serverOptions.completionOptions.serverSideFiltering = completionServerSideFiltering
    serverOptions.completionOptions.maxResults = completionMaxResults
    serverOptions.generatedInterfacesPath = generatedInterfacesPath

    return serverOptions
  }

  func run() throws {
    if let logLevel = logLevel {
      Logger.shared.currentLevel = logLevel
    } else {
      Logger.shared.setLogLevel(environmentVariable: "SOURCEKIT_LOGGING")
    }

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

    let clientConnection = JSONRPCConnection(
      protocol: MessageRegistry.lspProtocol,
      inFD: FileHandle.standardInput,
      outFD: realStdoutHandle,
      syncRequests: syncRequests
    )

    let installPath = AbsolutePath(Bundle.main.bundlePath)
    ToolchainRegistry.shared = ToolchainRegistry(installPath: installPath, localFileSystem)

    let server = SourceKitServer(client: clientConnection, options: mapOptions(), onExit: {
      clientConnection.close()
    })
    clientConnection.start(receiveHandler: server, closeHandler: {
      server.prepareForExit()
      // FIXME: keep the FileHandle alive until we close the connection to
      // workaround SR-13822.
      withExtendedLifetime(realStdoutHandle) {}
      // Use _Exit to avoid running static destructors due to SR-12668.
      _Exit(0)
    })

    dispatchMain()
  }
}

Main.main()
