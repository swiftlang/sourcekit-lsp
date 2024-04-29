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
import LSPLogging
import LanguageServerProtocol
import SKSupport

import struct Foundation.URL
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import struct TSCBasic.RelativePath
import var TSCBasic.localFileSystem

/// A `BuildSystem` based on loading clang-compatible compilation database(s).
///
/// Provides build settings from a `CompilationDatabase` found by searching a project. For now, only
/// one compilation database, located at the project root.
public actor CompilationDatabaseBuildSystem {
  /// The compilation database.
  var compdb: CompilationDatabase? = nil {
    didSet {
      // Build settings have changed and thus the index store path might have changed.
      // Recompute it on demand.
      _indexStorePath = nil
    }
  }

  /// Delegate to handle any build system events.
  public weak var delegate: BuildSystemDelegate? = nil

  /// Callbacks that should be called if the list of possible test files has changed.
  public var testFilesDidChangeCallbacks: [() async -> Void] = []

  public func setDelegate(_ delegate: BuildSystemDelegate?) async {
    self.delegate = delegate
  }

  public let projectRoot: AbsolutePath

  let searchPaths: [RelativePath]

  let fileSystem: FileSystem

  /// The URIs for which the delegate has registered for change notifications,
  /// mapped to the language the delegate specified when registering for change notifications.
  var watchedFiles: Set<DocumentURI> = []

  private var _indexStorePath: AbsolutePath?
  public var indexStorePath: AbsolutePath? {
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

  public init?(
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

  public var indexDatabasePath: AbsolutePath? {
    indexStorePath?.parentDirectory.appending(component: "IndexDatabase")
  }

  public var indexPrefixMappings: [PathPrefixMapping] { return [] }

  public func buildSettings(for document: DocumentURI, language: Language) async -> FileBuildSettings? {
    guard let url = document.fileURL else {
      // We can't determine build settings for non-file URIs.
      return nil
    }
    guard let db = database(for: url),
      let cmd = db[url].first
    else { return nil }
    return FileBuildSettings(
      compilerArguments: Array(cmd.commandLine.dropFirst()),
      workingDirectory: cmd.directory
    )
  }

  public func registerForChangeNotifications(for uri: DocumentURI) async {
    self.watchedFiles.insert(uri)
  }

  /// We don't support change watching.
  public func unregisterForChangeNotifications(for uri: DocumentURI) {
    self.watchedFiles.remove(uri)
  }

  private func database(for url: URL) -> CompilationDatabase? {
    if let path = try? AbsolutePath(validating: url.path) {
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
      logger.error("could not open compilation database for \(path)")
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

  public func filesDidChange(_ events: [FileEvent]) async {
    if events.contains(where: { self.fileEventShouldTriggerCompilationDatabaseReload(event: $0) }) {
      await self.reloadCompilationDatabase()
    }
  }

  public func fileHandlingCapability(for uri: DocumentURI) -> FileHandlingCapability {
    guard let fileUrl = uri.fileURL else {
      return .unhandled
    }
    if database(for: fileUrl) != nil {
      return .handled
    } else {
      return .unhandled
    }
  }

  public func sourceFiles() async -> [SourceFileInfo] {
    guard let compdb else {
      return []
    }
    return compdb.allCommands.map {
      SourceFileInfo(uri: DocumentURI($0.url), mayContainTests: true)
    }
  }

  public func addSourceFilesDidChangeCallback(_ callback: @escaping () async -> Void) async {
    testFilesDidChangeCallbacks.append(callback)
  }
}
