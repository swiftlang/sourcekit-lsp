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

  package let projectRoot: AbsolutePath

  let searchPaths: [RelativePath]

  let fileSystem: FileSystem

  /// The URIs for which the delegate has registered for change notifications,
  /// mapped to the language the delegate specified when registering for change notifications.
  var watchedFiles: Set<DocumentURI> = []

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
    fileSystem: FileSystem = localFileSystem
  ) {
    self.fileSystem = fileSystem
    self.projectRoot = projectRoot
    self.searchPaths = searchPaths
    if let compdb = tryLoadCompilationDatabase(directory: projectRoot, additionalSearchPaths: searchPaths, fileSystem) {
      self.compdb = compdb
    } else {
      return nil
    }
  }
}

extension CompilationDatabaseBuildSystem: BuildSystem {
  package nonisolated var supportsPreparation: Bool { false }

  package var indexDatabasePath: AbsolutePath? {
    indexStorePath?.parentDirectory.appending(component: "IndexDatabase")
  }

  package func buildSettings(
    for document: DocumentURI,
    in buildTarget: ConfiguredTarget,
    language: Language
  ) async -> FileBuildSettings? {
    guard let db = database(for: document),
      let cmd = db[document].first
    else { return nil }
    return FileBuildSettings(
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

  package func configuredTargets(for document: DocumentURI) async -> [ConfiguredTarget] {
    return [ConfiguredTarget(targetID: "dummy", runDestinationID: "dummy")]
  }

  package func prepare(
    targets: [ConfiguredTarget],
    logMessageToIndexLog: @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void
  ) async throws {
    throw PrepareNotSupportedError()
  }

  package func generateBuildGraph(allowFileSystemWrites: Bool) {}

  package func topologicalSort(of targets: [ConfiguredTarget]) -> [ConfiguredTarget]? {
    return nil
  }

  package func targets(dependingOn targets: [ConfiguredTarget]) -> [ConfiguredTarget]? {
    return nil
  }

  package func registerForChangeNotifications(for uri: DocumentURI) async {
    self.watchedFiles.insert(uri)
  }

  /// We don't support change watching.
  package func unregisterForChangeNotifications(for uri: DocumentURI) {
    self.watchedFiles.remove(uri)
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

    if let delegate = self.delegate {
      await delegate.fileBuildSettingsChanged(self.watchedFiles)
    }
    for testFilesDidChangeCallback in testFilesDidChangeCallbacks {
      await testFilesDidChangeCallback()
    }
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    if events.contains(where: { self.fileEventShouldTriggerCompilationDatabaseReload(event: $0) }) {
      await self.reloadCompilationDatabase()
    }
  }

  package func fileHandlingCapability(for uri: DocumentURI) -> FileHandlingCapability {
    if database(for: uri) != nil {
      return .handled
    } else {
      return .unhandled
    }
  }

  package func sourceFiles() async -> [SourceFileInfo] {
    guard let compdb else {
      return []
    }
    return compdb.allCommands.map {
      SourceFileInfo(uri: $0.uri, isPartOfRootProject: true, mayContainTests: true)
    }
  }

  package func addSourceFilesDidChangeCallback(_ callback: @escaping () async -> Void) async {
    testFilesDidChangeCallbacks.append(callback)
  }
}
