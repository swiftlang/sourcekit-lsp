//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
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
import LSPLogging
import SKSupport
import TSCBasic

/// A `BuildSystem` based on communicating with a build server
///
/// Provides build settings from a build server launched based on a
/// `buildServer.json` configuration file provided in the repo root.
public final class BuildServerBuildSystem {

  let projectRoot: AbsolutePath
  let buildFolder: AbsolutePath?
  let serverConfig: BuildServerConfig
  let requestQueue: DispatchQueue

  var handler: BuildServerHandler?
  var buildServer: JSONRPCConnection?

  public private(set) var indexDatabasePath: AbsolutePath?
  public private(set) var indexStorePath: AbsolutePath?

  /// Delegate to handle any build system events.
  public weak var delegate: BuildSystemDelegate? {
    get { return self.handler?.delegate }
    set { self.handler?.delegate = newValue }
  }

  public init(projectRoot: AbsolutePath, buildFolder: AbsolutePath?, fileSystem: FileSystem = localFileSystem) throws {
    let configPath = projectRoot.appending(component: "buildServer.json")
    let config = try loadBuildServerConfig(path: configPath, fileSystem: fileSystem)
    self.buildFolder = buildFolder
    self.projectRoot = projectRoot
    self.requestQueue = DispatchQueue(label: "build_server_request_queue")
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
    if let buildServer = self.buildServer {
      _ = buildServer.send(ShutdownBuild(), queue: DispatchQueue.global(), reply: { result in
        if let error = result.failure {
          log("error shutting down build server: \(error)")
        }
        buildServer.send(ExitBuildNotification())
        buildServer.close()
      })
    }
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
      rootUri: URI(self.projectRoot.asURL),
      capabilities: BuildClientCapabilities(languageIds: languages))

    let handler = BuildServerHandler()
    let buildServer = try makeJSONRPCBuildServer(client: handler, serverPath: serverPath, serverFlags: flags)
    let response = try buildServer.sendSync(initializeRequest)
    buildServer.send(InitializedBuildNotification())
    log("initialized build server \(response.displayName)")

    // see if index store was set as part of the server metadata
    if let indexDbPath = readReponseDataKey(data: response.data, key: "indexDatabasePath") {
      self.indexDatabasePath = AbsolutePath(indexDbPath, relativeTo: self.projectRoot)
    }
    if let indexStorePath = readReponseDataKey(data: response.data, key: "indexStorePath") {
      self.indexStorePath = AbsolutePath(indexStorePath, relativeTo: self.projectRoot)
    }
    self.buildServer = buildServer
    self.handler = handler
  }
}

private func readReponseDataKey(data: LSPAny?, key: String) -> String? {
  if case .dictionary(let dataDict)? = data,
    case .string(let stringVal)? = dataDict[key] {
    return stringVal
  }

  return nil
}

final class BuildServerHandler: LanguageServerEndpoint {

  public weak var delegate: BuildSystemDelegate? = nil

  override func _registerBuiltinHandlers() {
    _register(BuildServerHandler.handleBuildTargetsChanged)
    _register(BuildServerHandler.handleFileOptionsChanged)
  }

  func handleBuildTargetsChanged(_ notification: Notification<BuildTargetsChangedNotification>) {
    self.delegate?.buildTargetsChanged(notification.params.changes)
  }

  func handleFileOptionsChanged(_ notification: Notification<FileOptionsChangedNotification>) {
    let result = notification.params.updatedOptions
    let settings = FileBuildSettings(
        compilerArguments: result.options, workingDirectory: result.workingDirectory)
    self.delegate?.fileBuildSettingsChanged([notification.params.uri: .modified(settings)])
  }
}

extension BuildServerBuildSystem {
  /// Exposed for *testing*.
  public func _settings(for uri: DocumentURI) -> FileBuildSettings? {
    if let response = try? self.buildServer?.sendSync(SourceKitOptions(uri: uri)) {
      return FileBuildSettings(
        compilerArguments: response.options,
        workingDirectory: response.workingDirectory)
    }
    return nil
  }
}

extension BuildServerBuildSystem: BuildSystem {

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    let request = RegisterForChanges(uri: uri, action: .register)
    _ = self.buildServer?.send(request, queue: requestQueue, reply: { result in
      if let error = result.failure {
        log("error registering \(uri): \(error)", level: .error)

        // BuildServer registration failed, so tell our delegate that no build
        // settings are available.
        self.delegate?.fileBuildSettingsChanged([uri: .removedOrUnavailable])
      }
    })
  }

  /// Unregister the given file for build-system level change notifications, such as command
  /// line flag changes, dependency changes, etc.
  public func unregisterForChangeNotifications(for uri: DocumentURI) {
    let request = RegisterForChanges(uri: uri, action: .unregister)
    _ = self.buildServer?.send(request, queue: requestQueue, reply: { result in
      if let error = result.failure {
        log("error unregistering \(uri): \(error)", level: .error)
      }
    })
  }

  public func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    _ = self.buildServer?.send(BuildTargets(), queue: requestQueue) { response in
      switch response {
      case .success(let result):
        reply(.success(result.targets))
      case .failure(let error):
        reply(.failure(error))
      }
    }
  }

  public func buildTargetSources(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[SourcesItem]>) -> Void) {
    let req = BuildTargetSources(targets: targets)
    _ = self.buildServer?.send(req, queue: requestQueue) { response in
      switch response {
      case .success(let result):
        reply(.success(result.items))
      case .failure(let error):
        reply(.failure(error))
      }
    }
  }

  public func buildTargetOutputPaths(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[OutputsItem]>) -> Void) {
    let req = BuildTargetOutputPaths(targets: targets)
    _ = self.buildServer?.send(req, queue: requestQueue) { response in
      switch response {
      case .success(let result):
        reply(.success(result.items))
      case .failure(let error):
        reply(.failure(error))
      }
    }
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

private func makeJSONRPCBuildServer(client: MessageHandler, serverPath: AbsolutePath, serverFlags: [String]?) throws -> JSONRPCConnection {
  let clientToServer = Pipe()
  let serverToClient = Pipe()

  let connection = JSONRPCConnection(
    protocol: BuildServerProtocol.bspRegistry,
    inFD: serverToClient.fileHandleForReading,
    outFD: clientToServer.fileHandleForWriting
  )

  connection.start(receiveHandler: client) {
    // FIXME: keep the pipes alive until we close the connection. This
    // should be fixed systemically.
    withExtendedLifetime((clientToServer, serverToClient)) {}
  }
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
