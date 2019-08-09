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
  let buildFolder: AbsolutePath
  let buildServer: Connection
  let serverConfig: BuildServerConfig
  let handler: BuildServerHandler

  public init(projectRoot: AbsolutePath, buildFolder: AbsolutePath?, fileSystem: FileSystem = localFileSystem) throws {
    let configPath = projectRoot.appending(component: "buildServer.json")
    let config = try loadBuildServerConfig(path: configPath, fileSystem: fileSystem)

    self.buildFolder = buildFolder ?? AbsolutePath(config.indexStorePath, relativeTo: projectRoot)
    self.projectRoot = projectRoot
    self.serverConfig = config
    let serverPath = AbsolutePath(config.serverPath, relativeTo: projectRoot)
    self.handler = BuildServerHandler()
    self.buildServer = try makeJSONRPCBuildServer(client: self.handler, serverPath: serverPath, serverFlags: config.serverFlags)
  }

  /// Creates a build system using the Build Server Protocol config.
  ///
  /// - Returns: nil if `projectRoot` has no config or there is an error.
  public convenience init?(projectRoot: AbsolutePath?, buildSetup: BuildSetup)
  {
    if projectRoot == nil { return nil }

    do {
      try self.init(projectRoot: projectRoot!, buildFolder: buildSetup.path)
    } catch {
      log("failed to load build server config: \(error)", level: .error)
      return nil
    }
  }

}

final class BuildServerHandler: LanguageServerEndpoint {

  weak var delegate: BuildSystemDelegate?

  override func _registerBuiltinHandlers() {
    _register(BuildServerHandler.refreshDocuments)
  }

  func refreshDocuments(_ note: LanguageServerProtocol.Notification<RefereshDocumentsNotification>) {
    self.delegate?.refreshDocuments(note.params.uris)
  }

}

extension BuildServerBuildSystem: BuildSystem {

  public var delegate: BuildSystemDelegate? {
    get { return handler.delegate }
    set { handler.delegate = newValue }
  }

  public var indexStorePath: AbsolutePath? {
    return AbsolutePath(serverConfig.indexStorePath, relativeTo: projectRoot)
  }

  public var indexDatabasePath: AbsolutePath? {
    return buildFolder.appending(components: "index", "db")
  }

  public func settings(for url: URL, _ language: Language) -> FileBuildSettings? {
    do {
      let response = try buildServer.sendSync(FlagRequest(uri: url))
      return FileBuildSettings(compilerArguments: response.flags)
    } catch {
      return nil
    }
  }

  public func toolchain(for: URL, _ language: Language) -> Toolchain? {
    return nil
  }

}

private func loadBuildServerConfig(path: AbsolutePath, fileSystem: FileSystem) throws -> BuildServerConfig {
  return try BuildServerConfig(json: JSON.init(bytes: fileSystem.readFileContents(path)))
}

struct BuildServerConfig: JSONMappable {
  let indexStorePath: String
  let serverPath: String
  let serverFlags: [String]

  init(json: JSON) throws {
    indexStorePath = try json.get("indexStorePath")
    serverPath = try json.get("serverPath")
    serverFlags = try json.get("serverFlags")
  }
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
