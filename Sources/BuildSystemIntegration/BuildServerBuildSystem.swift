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
import SKLogging
import SKOptions
import SKSupport
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import struct TSCBasic.FileSystemError
import func TSCBasic.getEnvSearchPaths
import var TSCBasic.localFileSystem
import func TSCBasic.lookupExecutablePath
import func TSCBasic.resolveSymlinks

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
package actor BuildServerBuildSystem: MessageHandler {
  package let projectRoot: AbsolutePath
  let serverConfig: BuildServerConfig

  var buildServer: JSONRPCConnection?

  /// The queue on which all messages that originate from the build server are
  /// handled.
  ///
  /// These are requests and notifications sent *from* the build server,
  /// not replies from the build server.
  ///
  /// This ensures that messages from the build server are handled in the order
  /// they were received. Swift concurrency does not guarentee in-order
  /// execution of tasks.
  package let bspMessageHandlingQueue = AsyncQueue<Serial>()

  let searchPaths: [AbsolutePath]

  package private(set) var indexDatabasePath: AbsolutePath?
  package private(set) var indexStorePath: AbsolutePath?

  package weak var messageHandler: BuiltInBuildSystemMessageHandler?

  /// The build settings that have been received from the build server.
  private var buildSettings: [DocumentURI: SourceKitOptionsResponse] = [:]

  private var urisRegisteredForChanges: Set<URI> = []

  package init(
    projectRoot: AbsolutePath,
    messageHandler: BuiltInBuildSystemMessageHandler?,
    fileSystem: FileSystem = localFileSystem
  ) async throws {
    let configPath = projectRoot.appending(component: "buildServer.json")
    let config = try loadBuildServerConfig(path: configPath, fileSystem: fileSystem)
    #if os(Windows)
    self.searchPaths =
      getEnvSearchPaths(
        pathString: ProcessInfo.processInfo.environment["Path"],
        currentWorkingDirectory: fileSystem.currentWorkingDirectory
      )
    #else
    self.searchPaths =
      getEnvSearchPaths(
        pathString: ProcessInfo.processInfo.environment["PATH"],
        currentWorkingDirectory: fileSystem.currentWorkingDirectory
      )
    #endif
    self.projectRoot = projectRoot
    self.serverConfig = config
    self.messageHandler = messageHandler
    try await self.initializeBuildServer()
  }

  /// Creates a build system using the Build Server Protocol config.
  ///
  /// - Returns: nil if `projectRoot` has no config or there is an error parsing it.
  package init?(projectRoot: AbsolutePath?, messageHandler: BuiltInBuildSystemMessageHandler?) async {
    guard let projectRoot else { return nil }

    do {
      try await self.init(projectRoot: projectRoot, messageHandler: messageHandler)
    } catch is FileSystemError {
      // config file was missing, no build server for this workspace
      return nil
    } catch {
      logger.fault("Failed to start build server: \(error.forLogging)")
      return nil
    }
  }

  deinit {
    if let buildServer = self.buildServer {
      _ = buildServer.send(ShutdownBuild()) { result in
        if let error = result.failure {
          logger.fault("Error shutting down build server: \(error.forLogging)")
        }
        buildServer.send(ExitBuildNotification())
        buildServer.close()
      }
    }
  }

  private func initializeBuildServer() async throws {
    var serverPath = try AbsolutePath(validating: serverConfig.argv[0], relativeTo: projectRoot)
    var flags = Array(serverConfig.argv[1...])
    if serverPath.suffix == ".py" {
      flags = [serverPath.pathString] + flags
      guard
        let interpreterPath =
          lookupExecutablePath(
            filename: executable("python3"),
            searchPaths: searchPaths
          )
          ?? lookupExecutablePath(
            filename: executable("python"),
            searchPaths: searchPaths
          )
      else {
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

    let initializeRequest = InitializeBuildRequest(
      displayName: "SourceKit-LSP",
      version: "1.0",
      bspVersion: "2.0",
      rootUri: URI(self.projectRoot.asURL),
      capabilities: BuildClientCapabilities(languageIds: languages)
    )

    let buildServer = try makeJSONRPCBuildServer(client: self, serverPath: serverPath, serverFlags: flags)
    let response = try await buildServer.send(initializeRequest)
    buildServer.send(InitializedBuildNotification())
    logger.log("Initialized build server \(response.displayName)")

    // see if index store was set as part of the server metadata
    if let indexDbPath = readResponseDataKey(data: response.data, key: "indexDatabasePath") {
      self.indexDatabasePath = try AbsolutePath(validating: indexDbPath, relativeTo: self.projectRoot)
    }
    if let indexStorePath = readResponseDataKey(data: response.data, key: "indexStorePath") {
      self.indexStorePath = try AbsolutePath(validating: indexStorePath, relativeTo: self.projectRoot)
    }
    self.buildServer = buildServer
  }

  /// Handler for notifications received **from** the builder server, ie.
  /// the build server has sent us a notification.
  ///
  /// We need to notify the delegate about any updated build settings.
  package nonisolated func handle(_ params: some NotificationType) {
    logger.info(
      """
      Received notification from build server:
      \(params.forLogging)
      """
    )
    bspMessageHandlingQueue.async {
      if let params = params as? DidChangeBuildTargetNotification {
        await self.handleBuildTargetsChanged(params)
      } else if let params = params as? FileOptionsChangedNotification {
        await self.handleFileOptionsChanged(params)
      }
    }
  }

  /// Handler for requests received **from** the build server.
  ///
  /// We currently can't handle any requests sent from the build server to us.
  package nonisolated func handle<R: RequestType>(
    _ params: R,
    id: RequestID,
    reply: @escaping (LSPResult<R.Response>) -> Void
  ) {
    logger.info(
      """
      Received request from build server:
      \(params.forLogging)
      """
    )
    reply(.failure(ResponseError.methodNotFound(R.method)))
  }

  func handleBuildTargetsChanged(_ notification: DidChangeBuildTargetNotification) async {
    await self.messageHandler?.sendNotificationToSourceKitLSP(notification)
  }

  func handleFileOptionsChanged(_ notification: FileOptionsChangedNotification) async {
    let result = notification.updatedOptions
    let settings = SourceKitOptionsResponse(
      compilerArguments: result.options,
      workingDirectory: result.workingDirectory
    )
    await self.buildSettingsChanged(for: notification.uri, settings: settings)
  }

  /// Record the new build settings for the given document and inform the delegate
  /// about the changed build settings.
  private func buildSettingsChanged(for document: DocumentURI, settings: SourceKitOptionsResponse?) async {
    buildSettings[document] = settings
    // FIXME: (BSP migration) When running in the legacy mode where teh BSP server pushes build settings to us, we could
    // consider having a separate target for each source file so that we can update individual targets instead of having
    // to send an update for all targets.
    await self.messageHandler?.sendNotificationToSourceKitLSP(DidChangeBuildTargetNotification(changes: nil))
  }
}

private func readResponseDataKey(data: LSPAny?, key: String) -> String? {
  if case .dictionary(let dataDict)? = data,
    case .string(let stringVal)? = dataDict[key]
  {
    return stringVal
  }

  return nil
}

extension BuildServerBuildSystem: BuiltInBuildSystem {
  static package func projectRoot(for workspaceFolder: AbsolutePath, options: SourceKitLSPOptions) -> AbsolutePath? {
    guard localFileSystem.isFile(workspaceFolder.appending(component: "buildServer.json")) else {
      return nil
    }
    return workspaceFolder
  }

  package nonisolated var supportsPreparation: Bool { false }

  package func buildTargets(request: BuildTargetsRequest) async throws -> BuildTargetsResponse {
    // TODO: (BSP migration) Forward this request to the BSP server
    return BuildTargetsResponse(targets: [
      BuildTarget(
        id: .dummy,
        displayName: "Compilation database",
        baseDirectory: nil,
        tags: [.test],
        capabilities: BuildTargetCapabilities(),
        // Be conservative with the languages that might be used in the target. SourceKit-LSP doesn't use this property.
        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
        dependencies: []
      )
    ])
  }

  package func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
    // BuildServerBuildSystem does not support syntactic test discovery or background indexing.
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1173).
    // TODO: (BSP migration) Forward this request to the BSP server
    return BuildTargetSourcesResponse(items: [])
  }

  package func inverseSources(request: InverseSourcesRequest) -> InverseSourcesResponse {
    return InverseSourcesResponse(targets: [BuildTargetIdentifier.dummy])
  }

  package func didChangeWatchedFiles(notification: BuildServerProtocol.DidChangeWatchedFilesNotification) {}

  package func prepare(request: PrepareTargetsRequest) async throws -> VoidResponse {
    throw PrepareNotSupportedError()
  }

  package func sourceKitOptions(request: SourceKitOptionsRequest) async throws -> SourceKitOptionsResponse? {
    // FIXME: (BSP Migration) If the BSP server supports it, send the `SourceKitOptions` request to it. Only do the
    // `RegisterForChanges` dance if we are in the legacy mode.

    // Support the pre Swift 6.1 build settings workflow where SourceKit-LSP registers for changes for a file and then
    // expects updates to those build settings to get pushed to SourceKit-LSP with `FileOptionsChangedNotification`.
    // We do so by registering for changes when requesting build settings for a document for the first time. We never
    // unregister for changes. The expectation is that all BSP servers migrate to the `SourceKitOptionsRequest` soon,
    // which renders this code path dead.
    let uri = request.textDocument.uri
    if !urisRegisteredForChanges.contains(uri) {
      let request = RegisterForChanges(uri: uri, action: .register)
      _ = self.buildServer?.send(request) { result in
        if let error = result.failure {
          logger.error("Error registering \(request.uri): \(error.forLogging)")

          Task {
            // BuildServer registration failed, so tell our delegate that no build
            // settings are available.
            await self.buildSettingsChanged(for: request.uri, settings: nil)
          }
        }
      }
    }

    guard let buildSettings = buildSettings[uri] else {
      return nil
    }

    return SourceKitOptionsResponse(
      compilerArguments: buildSettings.compilerArguments,
      workingDirectory: buildSettings.workingDirectory
    )
  }

  package func waitForUpBuildSystemUpdates(request: WaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }

  package func addSourceFilesDidChangeCallback(_ callback: @escaping () async -> Void) {
    // BuildServerBuildSystem does not support syntactic test discovery or background indexing.
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1173).
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

private func makeJSONRPCBuildServer(
  client: MessageHandler,
  serverPath: AbsolutePath,
  serverFlags: [String]?
) throws -> JSONRPCConnection {
  let clientToServer = Pipe()
  let serverToClient = Pipe()

  let connection = JSONRPCConnection(
    name: "build server",
    protocol: BuildServerProtocol.bspRegistry,
    inFD: serverToClient.fileHandleForReading,
    outFD: clientToServer.fileHandleForWriting
  )

  connection.start(receiveHandler: client) {
    // Keep the pipes alive until we close the connection.
    withExtendedLifetime((clientToServer, serverToClient)) {}
  }
  let process = Foundation.Process()
  process.executableURL = serverPath.asURL
  process.arguments = serverFlags
  process.standardOutput = serverToClient
  process.standardInput = clientToServer
  process.terminationHandler = { process in
    logger.log(
      level: process.terminationReason == .exit ? .default : .error,
      "Build server exited: \(String(reflecting: process.terminationReason)) \(process.terminationStatus)"
    )
    connection.close()
  }
  try process.run()
  return connection
}
