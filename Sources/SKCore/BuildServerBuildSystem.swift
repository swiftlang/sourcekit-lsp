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
import Basic
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKSupport
import Foundation
import BuildServerProtocol

/// A `BuildSystem` based on communicating with a build server
///
/// Provides build settings from a build server launched based on a
/// `buildServer.json` configuration file provided in the repo root.
public final class BuildServerBuildSystem {

  let projectRoot: AbsolutePath
  let buildFolder: AbsolutePath?
  let serverConfig: BuildServerConfig

  var handler: BuildServerHandler?
  var buildServer: Connection?
  public private(set) var indexStorePath: AbsolutePath?

  public init(projectRoot: AbsolutePath, buildFolder: AbsolutePath?, fileSystem: FileSystem = localFileSystem) throws {
    let configPath = projectRoot.appending(component: "buildServer.json")
    let config = try loadBuildServerConfig(path: configPath, fileSystem: fileSystem)
    self.buildFolder = buildFolder
    self.projectRoot = projectRoot
    self.serverConfig = config
    try self.initializeBuildServer()
  }

  /// Creates a build system using the Build Server Protocol config.
  ///
  /// - Returns: nil if `projectRoot` has no config or there is an error parsing it.
  public convenience init?(projectRoot: AbsolutePath?, buildSetup: BuildSetup)
  {
    if projectRoot == nil { return nil }

    do {
      try self.init(projectRoot: projectRoot!, buildFolder: buildSetup.path)
    } catch _ as FileSystemError {
      // config file was missing, no build server for this workspace
      return nil
    } catch {
      log("failed to start build server: \(error)", level: .error)
      return nil
    }
  }

  deinit {
    _ = try? self.buildServer?.sendSync(ShutdownBuild())
    self.buildServer?.send(ExitBuildNotification())
  }

  private func initializeBuildServer() throws {
    let serverPath = AbsolutePath(serverConfig.argv[0], relativeTo: projectRoot)
    let flags = Array(serverConfig.argv[1...])
    let languages = [
      Language.c,
      Language.cpp,
      Language.objective_c,
      Language.objective_cpp,
      Language.swift,
    ]

    let initializeRequest = InitializeBuild(
      displayName: "SourceKit-LSP",
      version: "1.0",
      bspVersion: "2.0",
      rootUri: self.projectRoot.asURL,
      capabilities: BuildClientCapabilities(languageIds: languages))

    let handler = BuildServerHandler()
    let buildServer = try makeJSONRPCBuildServer(client: handler, serverPath: serverPath, serverFlags: flags)
    let response = try buildServer.sendSync(initializeRequest)
    buildServer.send(InitializedBuildNotification())
    log("initialized build server \(response.displayName)")

    // see if index store was set as part of the server metadata
    if let indexStorePath = readReponseDataKey(data: response.data, key: "indexStorePath") {
      self.indexStorePath = AbsolutePath(indexStorePath, relativeTo: self.projectRoot)
    }
    self.buildServer = buildServer
    self.handler = handler
  }
}

private func readReponseDataKey(data: LSPAny?, key: String) -> String? {
  switch data {
  case .dictionary(let dataDict):
    if let val = dataDict[key] {
      switch val {
      case .string(let stringVal):
        return stringVal
      default:
        break
      }
  }
  default:
    break
  }

  return nil
}

final class BuildServerHandler: LanguageServerEndpoint {
  override func _registerBuiltinHandlers() { }
}

extension BuildServerBuildSystem: BuildSystem {

  public var indexDatabasePath: AbsolutePath? {
    return buildFolder?.appending(components: "index", "db")
  }

  public func settings(for url: URL, _ language: Language) -> FileBuildSettings? {
    // TODO: add `textDocument/sourceKitOptions` request and response
    return nil
  }

  public func toolchain(for: URL, _ language: Language) -> Toolchain? {
    return nil
  }

}

private func loadBuildServerConfig(path: AbsolutePath, fileSystem: FileSystem) throws -> BuildServerConfig {
  let decoder = JSONDecoder()
  let fileData = try fileSystem.readFileContents(path).contents
  return try decoder.decode(BuildServerConfig.self, from: Data(fileData))
}

struct BuildServerConfig: Codable {
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
}

private func makeJSONRPCBuildServer(client: MessageHandler, serverPath: AbsolutePath, serverFlags: [String]?) throws -> Connection {
  let clientToServer = Pipe()
  let serverToClient = Pipe()

  let connection = JSONRPCConection(
    protocol: BuildServerProtocol.bspRegistry,
    inFD: serverToClient.fileHandleForReading.fileDescriptor,
    outFD: clientToServer.fileHandleForWriting.fileDescriptor
  )

  connection.start(receiveHandler: client)
  let process = Foundation.Process()

  if #available(OSX 10.13, *) {
    process.executableURL = serverPath.asURL
  } else {
    process.launchPath = serverPath.pathString
  }

  process.arguments = serverFlags
  process.standardOutput = serverToClient
  process.standardInput = clientToServer
  process.terminationHandler = { process in
    log("build server exited: \(process.terminationReason) \(process.terminationStatus)")
    connection.close()
  }

  if #available(OSX 10.13, *) {
    try process.run()
  } else {
    process.launch()
  }

  return connection
}
