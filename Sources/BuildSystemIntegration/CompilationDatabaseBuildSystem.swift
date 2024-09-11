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
import Dispatch
import LanguageServerProtocol
import SKLogging
import SKOptions
import SKSupport
import ToolchainRegistry

import struct Foundation.URL
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import struct TSCBasic.RelativePath
import var TSCBasic.localFileSystem

/// A `BuildSystem` based on loading clang-compatible compilation database(s).
///
/// Provides build settings from a `CompilationDatabase` found by searching a project. For now, only
/// one compilation database, located at the project root.
package actor CompilationDatabaseBuildSystem {
  /// The compilation database.
  var compdb: CompilationDatabase? = nil {
    didSet {
      // Build settings have changed and thus the index store path might have changed.
      // Recompute it on demand.
      _indexStorePath = nil
    }
  }

  /// Delegate to handle any build system events.
  package weak var delegate: BuildSystemDelegate? = nil

  /// Callbacks that should be called if the list of possible test files has changed.
  package var testFilesDidChangeCallbacks: [() async -> Void] = []

  package func setDelegate(_ delegate: BuildSystemDelegate?) async {
    self.delegate = delegate
  }

  package weak var messageHandler: BuiltInBuildSystemMessageHandler?

  package let projectRoot: AbsolutePath

  let searchPaths: [RelativePath]

  let fileSystem: FileSystem

  private var _indexStorePath: AbsolutePath?
  package var indexStorePath: AbsolutePath? {
    if let indexStorePath = _indexStorePath {
      return indexStorePath
    }

    if let allCommands = self.compdb?.allCommands {
      for command in allCommands {
        let args = command.commandLine
        for i in args.indices.reversed() {
          if args[i] == "-index-store-path" && i != args.endIndex - 1 {
            _indexStorePath = try? AbsolutePath(validating: args[i + 1])
            return _indexStorePath
          }
        }
      }
    }
    return nil
  }

  package init?(
    projectRoot: AbsolutePath,
    searchPaths: [RelativePath],
    messageHandler: (any BuiltInBuildSystemMessageHandler)?,
    fileSystem: FileSystem = localFileSystem
  ) {
    self.fileSystem = fileSystem
    self.projectRoot = projectRoot
    self.searchPaths = searchPaths
    self.messageHandler = messageHandler
    if let compdb = tryLoadCompilationDatabase(directory: projectRoot, additionalSearchPaths: searchPaths, fileSystem) {
      self.compdb = compdb
    } else {
      return nil
    }
  }
}

extension CompilationDatabaseBuildSystem: BuiltInBuildSystem {
  static package func projectRoot(for workspaceFolder: AbsolutePath, options: SourceKitLSPOptions) -> AbsolutePath? {
    if tryLoadCompilationDatabase(directory: workspaceFolder) != nil {
      return workspaceFolder
    }
    return nil
  }

  package nonisolated var supportsPreparation: Bool { false }

  package var indexDatabasePath: AbsolutePath? {
    indexStorePath?.parentDirectory.appending(component: "IndexDatabase")
  }

  package func buildTargets(request: BuildTargetsRequest) async throws -> BuildTargetsResponse {
    return BuildTargetsResponse(targets: [
      BuildTarget(
        id: .dummy,
        displayName: nil,
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
    guard request.targets.contains(.dummy) else {
      return BuildTargetSourcesResponse(items: [])
    }
    guard let compdb else {
      return BuildTargetSourcesResponse(items: [])
    }
    let sources = compdb.allCommands.map {
      SourceItem(uri: $0.uri, kind: .file, generated: false)
    }
    return BuildTargetSourcesResponse(items: [SourcesItem(target: .dummy, sources: sources)])
  }

  package func didChangeWatchedFiles(notification: BuildServerProtocol.DidChangeWatchedFilesNotification) async {
    if notification.changes.contains(where: { self.fileEventShouldTriggerCompilationDatabaseReload(event: $0) }) {
      await self.reloadCompilationDatabase()
    }
  }

  package func inverseSources(request: InverseSourcesRequest) -> InverseSourcesResponse {
    return InverseSourcesResponse(targets: [BuildTargetIdentifier.dummy])
  }

  package func prepare(request: PrepareTargetsRequest) async throws -> VoidResponse {
    throw PrepareNotSupportedError()
  }

  package func sourceKitOptions(request: SourceKitOptionsRequest) async throws -> SourceKitOptionsResponse? {
    guard let db = database(for: request.textDocument.uri), let cmd = db[request.textDocument.uri].first else {
      return nil
    }
    return SourceKitOptionsResponse(
      compilerArguments: Array(cmd.commandLine.dropFirst()),
      workingDirectory: cmd.directory
    )
  }

  package func defaultLanguage(for document: DocumentURI) async -> Language? {
    return nil
  }

  package func toolchain(for uri: DocumentURI, _ language: Language) async -> Toolchain? {
    return nil
  }

  package func scheduleBuildGraphGeneration() {}

  package func waitForUpToDateBuildGraph() async {}

  package func topologicalSort(of targets: [BuildTargetIdentifier]) -> [BuildTargetIdentifier]? {
    return nil
  }

  package func targets(dependingOn targets: [BuildTargetIdentifier]) -> [BuildTargetIdentifier]? {
    return nil
  }

  private func database(for uri: DocumentURI) -> CompilationDatabase? {
    if let url = uri.fileURL, let path = try? AbsolutePath(validating: url.path) {
      return database(for: path)
    }
    return compdb
  }

  private func database(for path: AbsolutePath) -> CompilationDatabase? {
    if compdb == nil {
      var dir = path
      while !dir.isRoot {
        dir = dir.parentDirectory
        if let db = tryLoadCompilationDatabase(directory: dir, additionalSearchPaths: searchPaths, fileSystem) {
          compdb = db
          break
        }
      }
    }

    if compdb == nil {
      logger.error("Could not open compilation database for \(path)")
    }

    return compdb
  }

  private func fileEventShouldTriggerCompilationDatabaseReload(event: FileEvent) -> Bool {
    switch event.uri.fileURL?.lastPathComponent {
    case "compile_commands.json", "compile_flags.txt":
      return true
    default:
      return false
    }
  }

  /// The compilation database has been changed on disk.
  /// Reload it and notify the delegate about build setting changes.
  private func reloadCompilationDatabase() async {
    self.compdb = tryLoadCompilationDatabase(
      directory: projectRoot,
      additionalSearchPaths: searchPaths,
      self.fileSystem
    )

    await messageHandler?.sendNotificationToSourceKitLSP(DidChangeBuildTargetNotification(changes: nil))
    for testFilesDidChangeCallback in testFilesDidChangeCallbacks {
      await testFilesDidChangeCallback()
    }
  }

  package func addSourceFilesDidChangeCallback(_ callback: @escaping () async -> Void) async {
    testFilesDidChangeCallbacks.append(callback)
  }
}
