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

import func TSCBasic.getEnvSearchPaths
import func TSCBasic.lookupExecutablePath
import func TSCBasic.resolveSymlinks
import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath
import struct TSCBasic.FileSystemError
import var TSCBasic.localFileSystem

enum BuildServerTestError: Error {
    case executableNotFound(String)
}

func executable(_ name: String) -> String {
#if os(Windows)
  guard !name.hasSuffix(".exe") else { return name }
  return "\(name).exe"
#else
  return name
#endif
}


/// A `BuildSystem` based on communicating with a build server
///
/// Provides build settings from a build server launched based on a
/// `buildServer.json` configuration file provided in the repo root.
public final class BuildServerBuildSystem: MessageHandler {
  /// The handler's request queue. `delegate` will always be called on this queue.
  public let queue: DispatchQueue = DispatchQueue(label: "language-server-queue", qos: .userInitiated)

  let projectRoot: AbsolutePath
  let buildFolder: AbsolutePath?
  let serverConfig: BuildServerConfig
  let requestQueue: DispatchQueue

  var buildServer: JSONRPCConnection?

  let searchPaths: [AbsolutePath]

  public private(set) var indexDatabasePath: AbsolutePath?
  public private(set) var indexStorePath: AbsolutePath?

  // FIXME: Add support for prefix mappings to the Build Server protocol.
  public var indexPrefixMappings: [PathPrefixMapping] { return [] }

  /// Delegate to handle any build system events.
  public weak var delegate: BuildSystemDelegate?

  /// The build settings that have been received from the build server.
  private var buildSettings: [DocumentURI: FileBuildSettings] = [:]

  public init(projectRoot: AbsolutePath, buildFolder: AbsolutePath?, fileSystem: FileSystem = localFileSystem) throws {
    let configPath = projectRoot.appending(component: "buildServer.json")
    let config = try loadBuildServerConfig(path: configPath, fileSystem: fileSystem)
#if os(Windows)
    self.searchPaths =
        getEnvSearchPaths(pathString: ProcessInfo.processInfo.environment["Path"],
                          currentWorkingDirectory: fileSystem.currentWorkingDirectory)
#else
    self.searchPaths =
        getEnvSearchPaths(pathString: ProcessInfo.processInfo.environment["PATH"],
                          currentWorkingDirectory: fileSystem.currentWorkingDirectory)
#endif
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
    var serverPath = try AbsolutePath(validating: serverConfig.argv[0], relativeTo: projectRoot)
    var flags = Array(serverConfig.argv[1...])
    if serverPath.suffix == ".py" {
      flags = [serverPath.pathString] + flags
      guard let interpreterPath =
          lookupExecutablePath(filename: executable("python3"),
                               searchPaths: searchPaths) ??
          lookupExecutablePath(filename: executable("python"),
                               searchPaths: searchPaths) else {
        throw BuildServerTestError.executableNotFound("python3")
      }

      serverPath = interpreterPath
    }
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

    let buildServer = try makeJSONRPCBuildServer(client: self, serverPath: serverPath, serverFlags: flags)
    let response = try buildServer.sendSync(initializeRequest)
    buildServer.send(InitializedBuildNotification())
    log("initialized build server \(response.displayName)")

    // see if index store was set as part of the server metadata
    if let indexDbPath = readReponseDataKey(data: response.data, key: "indexDatabasePath") {
      self.indexDatabasePath = try AbsolutePath(validating: indexDbPath, relativeTo: self.projectRoot)
    }
    if let indexStorePath = readReponseDataKey(data: response.data, key: "indexStorePath") {
      self.indexStorePath = try AbsolutePath(validating: indexStorePath, relativeTo: self.projectRoot)
    }
    self.buildServer = buildServer
  }

  /// Handler for notifications received **from** the builder server, ie.
  /// the build server has sent us a notification.
  ///
  /// We need to notify the delegate about any updated build settings.
  public func handle(_ params: some NotificationType, from clientID: ObjectIdentifier) {
    queue.async {
      if let params = params as? BuildTargetsChangedNotification {
        self.handleBuildTargetsChanged(Notification(params, clientID: clientID))
      } else if let params = params as? FileOptionsChangedNotification {
        self.handleFileOptionsChanged(Notification(params, clientID: clientID))
      }
    }
  }

  /// Handler for requests received **from** the build server.
  ///
  /// We currently can't handle any requests sent from the build server to us.
  public func handle<R: RequestType>(
    _ params: R,
    id: RequestID,
    from clientID: ObjectIdentifier,
    reply: @escaping (LSPResult<R.Response>) -> Void
  ) {
    queue.async {
      reply(.failure(ResponseError.methodNotFound(R.method)))
    }
  }

  func handleBuildTargetsChanged(_ notification: LanguageServerProtocol.Notification<BuildTargetsChangedNotification>) {
    self.delegate?.buildTargetsChanged(notification.params.changes)
  }

  func handleFileOptionsChanged(_ notification: LanguageServerProtocol.Notification<FileOptionsChangedNotification>) {
    let result = notification.params.updatedOptions
    let settings = FileBuildSettings(
        compilerArguments: result.options, workingDirectory: result.workingDirectory)
    self.buildSettingsChanged(for: notification.params.uri, settings: settings)
  }

  /// Record the new build settings for the given document and inform the delegate
  /// about the changed build settings.
  private func buildSettingsChanged(for document: DocumentURI, settings: FileBuildSettings?) {
    buildSettings[document] = settings
    if let settings {
      self.delegate?.fileBuildSettingsChanged([document: .modified(settings)])
    } else {
      self.delegate?.fileBuildSettingsChanged([document: .removedOrUnavailable])
    }
  }
}

private func readReponseDataKey(data: LSPAny?, key: String) -> String? {
  if case .dictionary(let dataDict)? = data,
    case .string(let stringVal)? = dataDict[key] {
    return stringVal
  }

  return nil
}

extension BuildServerBuildSystem: BuildSystem {
  /// The build settings for the given file.
  ///
  /// Returns `nil` if no build settings have been received from the build
  /// server yet or if no build settings are available for this file.
  public func buildSettings(for document: DocumentURI, language: Language) async throws -> FileBuildSettings? {
    return buildSettings[document]
  }

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    let request = RegisterForChanges(uri: uri, action: .register)
    _ = self.buildServer?.send(request, queue: requestQueue, reply: { result in
      if let error = result.failure {
        log("error registering \(uri): \(error)", level: .error)

        // BuildServer registration failed, so tell our delegate that no build
        // settings are available.
        self.buildSettingsChanged(for: uri, settings: nil)
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

  public func filesDidChange(_ events: [FileEvent]) {}

  public func fileHandlingCapability(for uri: DocumentURI) -> FileHandlingCapability {
    guard 
      let fileUrl = uri.fileURL, 
      let path = try? AbsolutePath(validating: fileUrl.path) 
    else {
      return .unhandled
    }

    // FIXME: We should not make any assumptions about which files the build server can handle.
    // Instead we should query the build server which files it can handle (#492).
    
    if projectRoot.isAncestorOfOrEqual(to: path) {
      return .handled
    }

    if let realpath = try? resolveSymlinks(path), realpath != path, projectRoot.isAncestorOfOrEqual(to: realpath) {
      return .handled
    }

    return .unhandled
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
  process.executableURL = serverPath.asURL
  process.arguments = serverFlags
  process.standardOutput = serverToClient
  process.standardInput = clientToServer
  process.terminationHandler = { process in
    log("build server exited: \(process.terminationReason) \(process.terminationStatus)")
    connection.close()
  }
  try process.run()
  return connection
}
