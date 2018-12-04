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

import SKSupport
import SKCore
import Basic
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import Foundation

/// A thin wrapper over a connection to a clangd server providing build setting handling.
final class ClangLanguageServerShim: LanguageServer {

  let clangd: Connection

  let buildSystem: BuildSystem

  /// Creates a language server for the given client using the sourcekitd dylib at the specified path.
  public init(client: Connection, clangd: Connection, buildSystem: BuildSystem) throws {

    self.clangd = clangd
    self.buildSystem = buildSystem
    super.init(client: client)
  }

  public override func _registerBuiltinHandlers() {
    _register(ClangLanguageServerShim.openDocument)
  }

  public override func _handleUnknown<R>(_ req: Request<R>) {
    var to: Connection
    if req.clientID == ObjectIdentifier(clangd) {
      to = client
    } else {
      to = clangd
    }

    let id = to.send(req.params, queue: queue) { result in
      req.reply(result)
    }
    req.cancellationToken.addCancellationHandler {
      to.send(CancelRequest(id: id))
    }
  }

  public override func _handleUnknown<N>(_ note: Notification<N>) {
    var to: Connection
    if note.clientID == ObjectIdentifier(clangd) {
      to = client
    } else {
      to = clangd
    }

    to.send(note.params)
  }

  func openDocument(_ note: Notification<DidOpenTextDocument>) {
    let url = note.params.textDocument.url
    let settings = buildSystem.settings(for: url, note.params.textDocument.language)

    logAsync(level: settings == nil ? .warning : .debug) { _ in
      let settingsStr = settings == nil ? "nil" : settings!.compilerArguments.description
      return "settings for \(url): \(settingsStr)"
    }

    if let settings = settings {
      clangd.send(DidChangeConfiguration(settings: .clangd(
        ClangWorkspaceSettings(
          compilationDatabaseChanges: [url.path: ClangCompileCommand(settings)]))))
    }

    clangd.send(note.params)
  }
}

func makeJSONRPCClangServer(client: MessageHandler, clangd: AbsolutePath, buildSettings: BuildSystem?) throws -> Connection {

  let clientToServer: Pipe = Pipe()
  let serverToClient: Pipe = Pipe()

  let connection = JSONRPCConection(
    inFD: serverToClient.fileHandleForReading.fileDescriptor,
    outFD: clientToServer.fileHandleForWriting.fileDescriptor
  )

  let connectionToShim = LocalConnection()
  let connectionToClient = LocalConnection()

  let shim = try ClangLanguageServerShim(
    client: connectionToClient,
    clangd: connection,
    buildSystem: buildSettings ?? BuildSystemList()
  )

  connectionToShim.start(handler: shim)
  connectionToClient.start(handler: client)
  connection.start(receiveHandler: shim)

  let process = Foundation.Process()

  if #available(OSX 10.13, *) {
    process.executableURL = clangd.asURL
  } else {
    process.launchPath = clangd.asString
  }

  process.arguments = [
    "-compile_args_from=lsp", // Provide compiler args programmatically.
  ]
  process.standardOutput = serverToClient
  process.standardInput = clientToServer
  process.terminationHandler = { process in
    log("clangd exited: \(process.terminationReason) \(process.terminationStatus)")
    connection.close()
  }

  if #available(OSX 10.13, *) {
    try process.run()
  } else {
    process.launch()
  }

  return connectionToShim
}

extension ClangCompileCommand {
  init(_ settings: FileBuildSettings) {
    // Clang expects the first argument to be the program name, like argv.
    self.init(
      compilationCommand: ["clang"] + settings.compilerArguments,
      workingDirectory: settings.workingDirectory ?? "")
  }
}
