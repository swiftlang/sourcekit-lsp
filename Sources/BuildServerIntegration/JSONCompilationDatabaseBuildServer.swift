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

package import BuildServerProtocol
package import Foundation
package import LanguageServerProtocol
import SKLogging
import SwiftExtensions
package import ToolchainRegistry

fileprivate extension CompilationDatabaseCompileCommand {
  /// The first entry in the command line identifies the compiler that should be used to compile the file and can thus
  /// be used to infer the toolchain.
  ///
  /// Note that this compiler does not necessarily need to exist on disk. Eg. tools may just use `clang` as the compiler
  /// without specifying a path.
  ///
  /// The absence of a compiler means we have an empty command line, which should never happen.
  ///
  /// If the compiler is a symlink to `swiftly`, it uses `swiftlyResolver` to find the corresponding executable in a
  /// real toolchain and returns that executable.
  func compiler(swiftlyResolver: SwiftlyResolver) async -> String? {
    guard let compiler = commandLine.first else {
      return nil
    }
    let swiftlyResolved = await orLog("Resolving swiftly") {
      try await swiftlyResolver.resolve(
        compiler: URL(fileURLWithPath: compiler),
        workingDirectory: URL(fileURLWithPath: directory)
      )?.filePath
    }
    if let swiftlyResolved {
      return swiftlyResolved
    }
    return compiler
  }
}

/// A `BuiltInBuildServer` that provides compiler arguments from a `compile_commands.json` file.
package actor JSONCompilationDatabaseBuildServer: BuiltInBuildServer {
  package static let dbName: String = "compile_commands.json"

  /// The compilation database.
  var compdb: JSONCompilationDatabase {
    didSet {
      // Build settings have changed and thus the index store path might have changed.
      // Recompute it on demand.
      _indexStorePath.reset()
    }
  }

  private let toolchainRegistry: ToolchainRegistry

  private let connectionToSourceKitLSP: any Connection

  package let configPath: URL

  private let swiftlyResolver = SwiftlyResolver()

  // Watch for all all changes to `compile_commands.json` and `compile_flags.txt` instead of just the one at
  // `configPath` so that we cover the following semi-common scenario:
  // The user has a build that stores `compile_commands.json` in `mybuild`. In order to pick it  up, they create a
  // symlink from `<project root>/compile_commands.json` to `mybuild/compile_commands.json`.  We want to get notified
  // about the change to `mybuild/compile_commands.json` because it effectively changes the contents of
  // `<project root>/compile_commands.json`.
  package let fileWatchers: [FileSystemWatcher] = [
    FileSystemWatcher(globPattern: "**/compile_commands.json", kind: [.create, .change, .delete]),
    FileSystemWatcher(globPattern: "**/.swift-version", kind: [.create, .change, .delete]),
  ]

  private var _indexStorePath: LazyValue<URL?> = .uninitialized
  package var indexStorePath: URL? {
    _indexStorePath.cachedValueOrCompute {
      for command in compdb.commands {
        if let indexStorePath = lastIndexStorePathArgument(in: command.commandLine) {
          return URL(
            fileURLWithPath: indexStorePath,
            relativeTo: URL(fileURLWithPath: command.directory, isDirectory: true)
          )
        }
      }
      return nil
    }
  }

  package var indexDatabasePath: URL? {
    indexStorePath?.deletingLastPathComponent().appendingPathComponent("IndexDatabase")
  }

  package nonisolated var supportsMultiTargetPreparation: Bool { false }

  package nonisolated var supportsPreparationAndOutputPaths: Bool { false }

  package init(
    configPath: URL,
    toolchainRegistry: ToolchainRegistry,
    connectionToSourceKitLSP: any Connection
  ) throws {
    self.compdb = try JSONCompilationDatabase(file: configPath)
    self.toolchainRegistry = toolchainRegistry
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
    self.configPath = configPath
  }

  package func buildTargets(request: WorkspaceBuildTargetsRequest) async throws -> WorkspaceBuildTargetsResponse {
    let compilers = Set(
      await compdb.commands.asyncCompactMap { (command) -> String? in
        await command.compiler(swiftlyResolver: swiftlyResolver)
      }
    ).sorted { $0 < $1 }
    let targets = try await compilers.asyncMap { compiler in
      let toolchainUri: URI? =
        if let toolchainPath = await toolchainRegistry.toolchain(withCompiler: URL(fileURLWithPath: compiler))?.path {
          URI(toolchainPath)
        } else {
          nil
        }
      return BuildTarget(
        id: try BuildTargetIdentifier.createCompileCommands(compiler: compiler),
        tags: [.test],
        capabilities: BuildTargetCapabilities(),
        // Be conservative with the languages that might be used in the target. SourceKit-LSP doesn't use this property.
        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
        dependencies: [],
        dataKind: .sourceKit,
        data: SourceKitBuildTarget(toolchain: toolchainUri).encodeToLSPAny()
      )
    }
    return WorkspaceBuildTargetsResponse(targets: targets)
  }

  package func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
    let items = await request.targets.asyncCompactMap { (target) -> SourcesItem? in
      guard let targetCompiler = orLog("Compiler for target", { try target.compileCommandsCompiler }) else {
        return nil
      }
      let commandsWithRequestedCompilers = await compdb.commands.lazy.asyncFilter { command in
        return await targetCompiler == command.compiler(swiftlyResolver: swiftlyResolver)
      }
      let sources = commandsWithRequestedCompilers.map {
        SourceItem(uri: $0.uri, kind: .file, generated: false)
      }
      return SourcesItem(target: target, sources: Array(sources))
    }

    return BuildTargetSourcesResponse(items: items)
  }

  package func didChangeWatchedFiles(notification: OnWatchedFilesDidChangeNotification) async {
    if notification.changes.contains(where: { $0.uri.fileURL?.lastPathComponent == Self.dbName }) {
      self.reloadCompilationDatabase()
    }
    if notification.changes.contains(where: { $0.uri.fileURL?.lastPathComponent == ".swift-version" }) {
      await swiftlyResolver.clearCache()
      connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
    }
  }

  package func prepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    throw ResponseError.methodNotFound(BuildTargetPrepareRequest.method)
  }

  package func sourceKitOptions(
    request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    let targetCompiler = try request.target.compileCommandsCompiler
    let command = await compdb[request.textDocument.uri].asyncFilter {
      return await $0.compiler(swiftlyResolver: swiftlyResolver) == targetCompiler
    }.first
    guard let command else {
      return nil
    }
    return TextDocumentSourceKitOptionsResponse(
      compilerArguments: Array(command.commandLine.dropFirst()),
      workingDirectory: command.directory
    )
  }

  package func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }

  /// The compilation database has been changed on disk.
  /// Reload it and notify the delegate about build setting changes.
  private func reloadCompilationDatabase() {
    orLog("Reloading compilation database") {
      self.compdb = try JSONCompilationDatabase(file: configPath)
      connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
    }
  }
}
