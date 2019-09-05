//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceKit
import LanguageServerProtocolJSONRPC
import LanguageServerProtocol
import SKSupport
import SKCore
import TSCLibc
import Dispatch
import TSCBasic
import TSCUtility
import Foundation
import sourcekitd // Not needed here, but fixes debugging...

func parseArguments() throws -> (BuildSetup, sync: Bool) {
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

  let parsedArguments = try parser.parse(arguments)

  var buildFlags = BuildSetup.default.flags
  buildFlags.cCompilerFlags = parsedArguments.get(buildFlagsCc) ?? []
  buildFlags.cxxCompilerFlags = parsedArguments.get(buildFlagsCxx) ?? []
  buildFlags.linkerFlags = parsedArguments.get(buildFlagsLinker) ?? []
  buildFlags.swiftCompilerFlags = parsedArguments.get(buildFlagsSwift) ?? []

  if let logLevel = parsedArguments.get(loggingOption) {
    Logger.shared.currentLevel = logLevel
  } else {
    Logger.shared.setLogLevel(environmentVariable: "SOURCEKIT_LOGGING")
  }

  let sync = parsedArguments.get(syncOption) ?? false

  return (BuildSetup(
    configuration: parsedArguments.get(buildConfigurationOption) ?? BuildSetup.default.configuration,
    path: parsedArguments.get(buildPathOption)?.path,
    flags: buildFlags),
    sync: sync)
}

let buildSetup: BuildSetup
let sync: Bool
do {
  (buildSetup, sync) = try parseArguments()
} catch {
  fputs("error: \(error)\n", TSCLibc.stderr)
  exit(1)
}

let clientConnection = JSONRPCConection(
  protocol: MessageRegistry.lspProtocol,
  inFD: STDIN_FILENO,
  outFD: STDOUT_FILENO,
  syncRequests: sync,
  closeHandler: {
  exit(0)
})

Logger.shared.addLogHandler { message, _ in
  clientConnection.send(LogMessage(type: .log, message: message))
}

let installPath = AbsolutePath(Bundle.main.bundlePath)
ToolchainRegistry.shared = ToolchainRegistry(installPath: installPath, localFileSystem)

let server = SourceKitServer(client: clientConnection, buildSetup: buildSetup, onExit: {
  clientConnection.close()
})
clientConnection.start(receiveHandler: server)

dispatchMain()
