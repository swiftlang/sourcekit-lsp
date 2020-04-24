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

import Dispatch
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import LSPLogging
import SKCore
import SKSupport
import SourceKit
import sourcekitd // Not needed here, but fixes debugging...
import TSCBasic
import TSCLibc
import TSCUtility

extension LogLevel: ArgumentKind {
  public static var completion: ShellCompletion {
    return ShellCompletion.none
  }
}

struct CommandLineOptions {
  /// Options for the server.
  var serverOptions: SourceKitServer.Options = SourceKitServer.Options()

  /// Whether to wait for a response before handling the next request.
  var syncRequests: Bool = false
}

func parseArguments() throws -> CommandLineOptions {
  let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
  let parser = ArgumentParser(usage: "[options]", overview: "Language Server Protocol implementation for Swift and C-based languages")
  let loggingOption = parser.add(option: "--log-level", kind: LogLevel.self, usage: "Set the logging level (debug|info|warning|error) [default: \(LogLevel.default)]")
  let syncOption = parser.add(option: "--sync", kind: Bool.self) // For testing.
  let buildConfigurationOption = parser.add(option: "--configuration", shortName: "-c", kind: BuildConfiguration.self, usage: "Build with configuration (debug|release) [default: debug]")
  let buildPathOption = parser.add(option: "--build-path", kind: PathArgument.self, usage: "Specify build/cache directory")
  let buildFlagsCc = parser.add(option: "-Xcc", kind: [String].self, strategy: .oneByOne, usage: "Pass flag through to all C compiler invocations")
  let buildFlagsCxx = parser.add(option: "-Xcxx", kind: [String].self, strategy: .oneByOne, usage: "Pass flag through to all C++ compiler invocations")
  let buildFlagsLinker = parser.add(option: "-Xlinker", kind: [String].self, strategy: .oneByOne, usage: "Pass flag through to all linker invocations")
  let buildFlagsSwift = parser.add(option: "-Xswiftc", kind: [String].self, strategy: .oneByOne, usage: "Pass flag through to all Swift compiler invocations")
  let clangdOptions = parser.add(option: "-Xclangd", kind: [String].self, strategy: .oneByOne, usage: "Pass options to clangd command-line")
  let indexStorePath = parser.add(option: "-index-store-path", kind: PathArgument.self, usage: "Override index-store-path from the build system")
  let indexDatabasePath = parser.add(option: "-index-db-path", kind: PathArgument.self, usage: "Override index-database-path from the build system")

  let parsedArguments = try parser.parse(arguments)

  var result = CommandLineOptions()

  if let config = parsedArguments.get(buildConfigurationOption) {
    result.serverOptions.buildSetup.configuration = config
  }
  if let buildPath = parsedArguments.get(buildPathOption)?.path {
    result.serverOptions.buildSetup.path = buildPath
  }
  if let flags = parsedArguments.get(buildFlagsCc) {
    result.serverOptions.buildSetup.flags.cCompilerFlags = flags
  }
  if let flags = parsedArguments.get(buildFlagsCxx) {
    result.serverOptions.buildSetup.flags.cxxCompilerFlags = flags
  }
  if let flags = parsedArguments.get(buildFlagsLinker) {
    result.serverOptions.buildSetup.flags.linkerFlags = flags
  }
  if let flags = parsedArguments.get(buildFlagsSwift) {
    result.serverOptions.buildSetup.flags.swiftCompilerFlags = flags
  }

  if let options = parsedArguments.get(clangdOptions) {
    result.serverOptions.clangdOptions = options
  }

  if let path = parsedArguments.get(indexStorePath)?.path {
    result.serverOptions.indexOptions.indexStorePath = path
  }
  if let path = parsedArguments.get(indexDatabasePath)?.path {
    result.serverOptions.indexOptions.indexDatabasePath = path
  }

  if let logLevel = parsedArguments.get(loggingOption) {
    Logger.shared.currentLevel = logLevel
  } else {
    Logger.shared.setLogLevel(environmentVariable: "SOURCEKIT_LOGGING")
  }

  if let sync = parsedArguments.get(syncOption) {
    result.syncRequests = sync
  }

  return result
}

let options: CommandLineOptions
do {
  options = try parseArguments()
} catch {
  fputs("error: \(error)\n", TSCLibc.stderr)
  exit(1)
}

let clientConnection = JSONRPCConnection(
  protocol: MessageRegistry.lspProtocol,
  inFD: STDIN_FILENO,
  outFD: STDOUT_FILENO,
  syncRequests: options.syncRequests)

let installPath = AbsolutePath(Bundle.main.bundlePath)
ToolchainRegistry.shared = ToolchainRegistry(installPath: installPath, localFileSystem)

let server = SourceKitServer(client: clientConnection, options: options.serverOptions, onExit: {
  clientConnection.close()
})
clientConnection.start(receiveHandler: server, closeHandler: {
  server.prepareForExit()
  // Use _Exit to avoid running static destructors due to SR-12668.
  _Exit(0)
})

Logger.shared.addLogHandler { message, _ in
  clientConnection.send(LogMessageNotification(type: .log, message: message))
}

dispatchMain()
