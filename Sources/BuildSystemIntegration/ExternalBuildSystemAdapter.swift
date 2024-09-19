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

import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKOptions

import struct TSCBasic.AbsolutePath
import func TSCBasic.getEnvSearchPaths
import var TSCBasic.localFileSystem
import func TSCBasic.lookupExecutablePath

private func executable(_ name: String) -> String {
  #if os(Windows)
  guard !name.hasSuffix(".exe") else { return name }
  return "\(name).exe"
  #else
  return name
  #endif
}

private let python3ExecutablePath: AbsolutePath? = {
  let pathVariable: String
  #if os(Windows)
  pathVariable = "Path"
  #else
  pathVariable = "PATH"
  #endif
  let searchPaths =
    getEnvSearchPaths(
      pathString: ProcessInfo.processInfo.environment[pathVariable],
      currentWorkingDirectory: localFileSystem.currentWorkingDirectory
    )

  return lookupExecutablePath(filename: executable("python3"), searchPaths: searchPaths)
    ?? lookupExecutablePath(filename: executable("python"), searchPaths: searchPaths)
}()

struct ExecutableNotFoundError: Error {
  let executableName: String
}

private struct BuildServerConfig: Codable {
  /// The name of the build tool.
  let name: String

  /// The version of the build tool.
  let version: String

  /// The bsp version of the build tool.
  let bspVersion: String

  /// A collection of languages supported by this BSP server.
  let languages: [String]

  /// Command arguments runnable via system processes to start a BSP server.
  let argv: [String]

  static func load(from path: AbsolutePath) throws -> BuildServerConfig {
    let decoder = JSONDecoder()
    let fileData = try localFileSystem.readFileContents(path).contents
    return try decoder.decode(BuildServerConfig.self, from: Data(fileData))
  }
}

/// Launches a subprocess that is a BSP server and manages the process's lifetime.
actor ExternalBuildSystemAdapter {
  /// The JSON-RPC connection between SourceKit-LSP and the BSP server.
  let connectionToBuildServer: JSONRPCConnection

  /// The `BuildSystemManager` that handles messages from the BSP server to SourceKit-LSP.
  let messagesToSourceKitLSPHandler: MessageHandler

  static package func projectRoot(for workspaceFolder: AbsolutePath, options: SourceKitLSPOptions) -> AbsolutePath? {
    guard localFileSystem.isFile(workspaceFolder.appending(component: "buildServer.json")) else {
      return nil
    }
    return workspaceFolder
  }

  init(
    projectRoot: AbsolutePath,
    messagesToSourceKitLSPHandler: MessageHandler
  ) async throws {
    self.messagesToSourceKitLSPHandler = messagesToSourceKitLSPHandler

    let configPath = projectRoot.appending(component: "buildServer.json")
    let serverConfig = try BuildServerConfig.load(from: configPath)
    var serverPath = try AbsolutePath(validating: serverConfig.argv[0], relativeTo: projectRoot)
    var serverArgs = Array(serverConfig.argv[1...])

    if serverPath.suffix == ".py" {
      serverArgs = [serverPath.pathString] + serverArgs
      guard let interpreterPath = python3ExecutablePath else {
        throw ExecutableNotFoundError(executableName: "python3")
      }

      serverPath = interpreterPath
    }

    connectionToBuildServer = try JSONRPCConnection.start(
      executable: serverPath.asURL,
      arguments: serverArgs,
      name: "BSP-Server",
      protocol: bspRegistry,
      stderrLoggingCategory: "bsp-server-stderr",
      client: messagesToSourceKitLSPHandler,
      terminationHandler: { _ in
        // TODO: Handle BSP server restart (https://github.com/swiftlang/sourcekit-lsp/issues/1686)
      }
    ).connection
  }
}
