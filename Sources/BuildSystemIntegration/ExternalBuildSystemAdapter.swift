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
import LanguageServerProtocolExtensions
import LanguageServerProtocolJSONRPC
import SKLogging
import SKOptions
import SwiftExtensions
import TSCExtensions

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

private let python3ExecutablePath: URL? = {
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

  return lookupExecutablePath(filename: executable("python3"), searchPaths: searchPaths)?.asURL
    ?? lookupExecutablePath(filename: executable("python"), searchPaths: searchPaths)?.asURL
}()

struct ExecutableNotFoundError: Error {
  let executableName: String
}

enum BuildServerNotFoundError: Error {
  case fileNotFound
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

  static func load(from path: URL) throws -> BuildServerConfig {
    let decoder = JSONDecoder()
    let fileData = try Data(contentsOf: path)
    return try decoder.decode(BuildServerConfig.self, from: fileData)
  }
}

/// Launches a subprocess that is a BSP server and manages the process's lifetime.
actor ExternalBuildSystemAdapter {
  private let projectRoot: URL

  /// The `BuildSystemManager` that handles messages from the BSP server to SourceKit-LSP.
  var messagesToSourceKitLSPHandler: MessageHandler

  /// The JSON-RPC connection between SourceKit-LSP and the BSP server.
  private(set) var connectionToBuildServer: JSONRPCConnection?

  /// After a `build/initialize` request has been sent to the BSP server, that request, so we can replay it in case the
  /// server crashes.
  private var initializeRequest: InitializeBuildRequest?

  /// The date at which `clangd` was last restarted.
  /// Used to delay restarting in case of a crash loop.
  private var lastRestart: Date?

  static package func projectRoot(for workspaceFolder: URL, options: SourceKitLSPOptions) -> URL? {
    guard getConfigPath(for: workspaceFolder) != nil else {
      return nil
    }
    return workspaceFolder
  }

  init(
    projectRoot: URL,
    messagesToSourceKitLSPHandler: MessageHandler
  ) async throws {
    self.projectRoot = projectRoot
    self.messagesToSourceKitLSPHandler = messagesToSourceKitLSPHandler
    self.connectionToBuildServer = try await self.createConnectionToBspServer()
  }

  /// Change the handler that handles messages from the build server.
  ///
  /// The intended use of this is to intercept messages from the build server by `LegacyBuildServerBuildSystem`.
  func changeMessageToSourceKitLSPHandler(to newHandler: MessageHandler) {
    messagesToSourceKitLSPHandler = newHandler
    connectionToBuildServer?.changeReceiveHandler(messagesToSourceKitLSPHandler)
  }

  /// Send a notification to the build server.
  func send(_ notification: some NotificationType) {
    guard let connectionToBuildServer else {
      logger.error("Dropping notification because BSP server has crashed: \(notification.forLogging)")
      return
    }
    connectionToBuildServer.send(notification)
  }

  /// Send a request to the build server.
  func send<Request: RequestType>(_ request: Request) async throws -> Request.Response {
    guard let connectionToBuildServer else {
      throw ResponseError.internalError("BSP server has crashed")
    }
    if let request = request as? InitializeBuildRequest {
      if initializeRequest != nil {
        logger.error("BSP server was initialized multiple times")
      }
      self.initializeRequest = request
    }
    return try await connectionToBuildServer.send(request)
  }

  /// Create a new JSONRPCConnection to the build server.
  private func createConnectionToBspServer() async throws -> JSONRPCConnection {
    guard let configPath = ExternalBuildSystemAdapter.getConfigPath(for: self.projectRoot) else {
      throw BuildServerNotFoundError.fileNotFound
    }

    let serverConfig = try BuildServerConfig.load(from: configPath)
    var serverPath = URL(fileURLWithPath: serverConfig.argv[0], relativeTo: projectRoot.ensuringCorrectTrailingSlash)
    var serverArgs = Array(serverConfig.argv[1...])

    if serverPath.pathExtension == "py" {
      serverArgs = [try serverPath.filePath] + serverArgs
      guard let interpreterPath = python3ExecutablePath else {
        throw ExecutableNotFoundError(executableName: "python3")
      }

      serverPath = interpreterPath
    }

    return try JSONRPCConnection.start(
      executable: serverPath,
      arguments: serverArgs,
      name: "BSP-Server",
      protocol: bspRegistry,
      stderrLoggingCategory: "bsp-server-stderr",
      client: messagesToSourceKitLSPHandler,
      terminationHandler: { [weak self] terminationStatus in
        guard let self else {
          return
        }
        if terminationStatus != 0 {
          Task {
            await orLog("Restarting BSP server") {
              try await self.handleBspServerCrash()
            }
          }
        }
      }
    ).connection
  }

  private static func getConfigPath(for workspaceFolder: URL? = nil) -> URL? {
    var buildServerConfigLocations: [URL?] = []
    if let workspaceFolder = workspaceFolder {
      buildServerConfigLocations.append(workspaceFolder.appendingPathComponent(".bsp"))
    }

    #if os(Windows)
    if let localAppData = ProcessInfo.processInfo.environment["LOCALAPPDATA"] {
      buildServerConfigLocations.append(URL(fileURLWithPath: localAppData).appendingPathComponent("bsp"))
    }
    if let programData = ProcessInfo.processInfo.environment["PROGRAMDATA"] {
      buildServerConfigLocations.append(URL(fileURLWithPath: programData).appendingPathComponent("bsp"))
    }
    #else
    if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
      buildServerConfigLocations.append(URL(fileURLWithPath: xdgDataHome).appendingPathComponent("bsp"))
    }

    if let libraryUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      buildServerConfigLocations.append(libraryUrl.appendingPathComponent("bsp"))
    }

    if let xdgDataDirs = ProcessInfo.processInfo.environment["XDG_DATA_DIRS"] {
      buildServerConfigLocations += xdgDataDirs.split(separator: ":").map { xdgDataDir in
        URL(fileURLWithPath: String(xdgDataDir)).appendingPathComponent("bsp")
      }
    }

    if let libraryUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .systemDomainMask).first {
      buildServerConfigLocations.append(libraryUrl.appendingPathComponent("bsp"))
    }
    #endif

    for case let buildServerConfigLocation? in buildServerConfigLocations {
      let jsonFiles =
        try? FileManager.default.contentsOfDirectory(at: buildServerConfigLocation, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }

      if let configFileURL = jsonFiles?.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
        return configFileURL
      }
    }

    // Pre Swift 6.1 SourceKit-LSP looked for `buildServer.json` in the project root. Maintain this search location for
    // compatibility even though it's not a standard BSP search location.
    if let buildServerPath = workspaceFolder?.appendingPathComponent("buildServer.json"),
      FileManager.default.isFile(at: buildServerPath)
    {
      return buildServerPath
    }

    return nil
  }

  /// Restart the BSP server after it has crashed.
  private func handleBspServerCrash() async throws {
    // Set `connectionToBuildServer` to `nil` to indicate that there is currently no BSP server running.
    connectionToBuildServer = nil

    guard let initializeRequest else {
      logger.error("BSP server crashed before it was sent an initialize request. Not restarting.")
      return
    }

    logger.error("The BSP server has crashed. Restarting.")
    let restartDelay: Duration
    if let lastClangdRestart = self.lastRestart, Date().timeIntervalSince(lastClangdRestart) < 30 {
      logger.log("BSP server has been restarted in the last 30 seconds. Delaying another restart by 10 seconds.")
      restartDelay = .seconds(10)
    } else {
      restartDelay = .zero
    }
    self.lastRestart = Date()

    try await Task.sleep(for: restartDelay)

    let restartedConnection = try await self.createConnectionToBspServer()

    // We assume that the server returns the same initialize response after being restarted.
    // BSP does not set any state from the client to the server, so there are no other requests we need to replay
    // (other than `textDocument/registerForChanges`, which is only used by the legacy BSP protocol, which didn't have
    // crash recovery and doesn't need to gain it because it is deprecated).
    _ = try await restartedConnection.send(initializeRequest)
    restartedConnection.send(OnBuildInitializedNotification())
    self.connectionToBuildServer = restartedConnection

    // The build targets might have changed after the restart. Send a `buildTarget/didChange` notification to
    // SourceKit-LSP to discard cached information.
    self.messagesToSourceKitLSPHandler.handle(OnBuildTargetDidChangeNotification(changes: nil))
  }
}

fileprivate extension URL {
  /// If the path of this URL represents a directory, ensure that it has a trailing slash.
  ///
  /// This is important because if we form a file URL relative to eg. file:///tmp/a would assumes that `a` is a file
  /// and use `/tmp` as the base, not `/tmp/a`.
  var ensuringCorrectTrailingSlash: URL {
    guard self.isFileURL else {
      return self
    }
    // `URL(fileURLWithPath:)` checks the file system to decide whether a directory exists at the path.
    return URL(fileURLWithPath: self.path)
  }
}
