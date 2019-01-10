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
import SPMLibc
import Dispatch
import Utility
import PackageModel
import Foundation
import sourcekitd // Not needed here, but fixes debugging...

func parseConfigurationArguments() throws -> SourceKitServer.Configuration {
  let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
  let parser = ArgumentParser(usage: "[options]", overview: "Language Server Protocol implementation for Swift and C-based languages")
  let buildConfigurationOption = parser.add(option: "--configuration", shortName: "-c", kind: BuildConfiguration.self, usage: "Build with configuration (debug|release) [default: debug]")
  let buildPathOption = parser.add(option: "--build-path", kind: String.self, usage: "Specify build/cache directory [default: ./.build]")
  let buildFlagsCc = parser.add(option: "-Xcc", kind: [String].self, usage: "Pass flag through to all C compiler invocations")
  let buildFlagsCxx = parser.add(option: "-Xcxx", kind: [String].self, usage: "Pass flag through to all C++ compiler invocations")
  let buildFlagsLinker = parser.add(option: "-Xlinker", kind: [String].self, usage: "Pass flag through to all linker invocations")
  let buildFlagsSwift = parser.add(option: "-Xswiftc", kind: [String].self, usage: "Pass flag through to all Swift compiler invocations")

  let parsedArguments = try parser.parse(arguments)

  var buildFlags = BuildFlags()
  buildFlags.cCompilerFlags = parsedArguments.get(buildFlagsCc) ?? []
  buildFlags.cxxCompilerFlags = parsedArguments.get(buildFlagsCxx) ?? []
  buildFlags.linkerFlags = parsedArguments.get(buildFlagsLinker) ?? []
  buildFlags.swiftCompilerFlags = parsedArguments.get(buildFlagsSwift) ?? []

  return SourceKitServer.Configuration(buildConfiguration: parsedArguments.get(buildConfigurationOption) ?? .debug,
                                       buildPath: parsedArguments.get(buildPathOption) ?? "./.build",
                                       buildFlags: buildFlags)
}

Logger.shared.setLogLevel(environmentVariable: "SOURCEKIT_LOGGING")

let clientConnection = JSONRPCConection(inFD: STDIN_FILENO, outFD: STDOUT_FILENO, closeHandler: {
  exit(0)
})

Logger.shared.addLogHandler { message, _ in
  clientConnection.send(LogMessage(type: .log, message: message))
}

let server = SourceKitServer(client: clientConnection, configuration: try parseConfigurationArguments(), onExit: {
  clientConnection.close()
})
clientConnection.start(receiveHandler: server)

dispatchMain()
