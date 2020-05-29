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
import LanguageServerProtocol
import LSPLogging
import SKSupport
import TSCBasic
import Dispatch
import struct Foundation.URL

/// A `BuildSystem` based on loading clang-compatible compilation database(s).
///
/// Provides build settings from a `CompilationDatabase` found by searching a project. For now, only
/// one compilation database, located at the project root.
public final class CompilationDatabaseBuildSystem {

  /// The compilation database.
  var compdb: CompilationDatabase? = nil

  /// Delegate to handle any build system events.
  public weak var delegate: BuildSystemDelegate? = nil

  let fileSystem: FileSystem

  public lazy var indexStorePath: AbsolutePath? = {
    if let allCommands = self.compdb?.allCommands {
      for command in allCommands {
        let args = command.commandLine
        for i in args.indices.reversed() {
          if args[i] == "-index-store-path" && i != args.endIndex - 1 {
            return try? AbsolutePath(validating: args[i+1])
          }
        }
      }
    }
    return nil
  }()

  public init(projectRoot: AbsolutePath? = nil, fileSystem: FileSystem = localFileSystem) {
    self.fileSystem = fileSystem
    if let path = projectRoot {
      self.compdb = tryLoadCompilationDatabase(directory: path, fileSystem)
    }
  }
}

extension CompilationDatabaseBuildSystem: BuildSystem {

  public var indexDatabasePath: AbsolutePath? {
    indexStorePath?.parentDirectory.appending(component: "IndexDatabase")
  }

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    guard let delegate = self.delegate else { return }

    let settings = self._settings(for: uri)
    DispatchQueue.global().async {
      delegate.fileBuildSettingsChanged([uri: FileBuildSettingsChange(settings)])
    }
  }

  /// We don't support change watching.
  public func unregisterForChangeNotifications(for: DocumentURI) {}

  public func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  public func buildTargetSources(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[SourcesItem]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  public func buildTargetOutputPaths(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[OutputsItem]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  func database(for url: URL) -> CompilationDatabase? {
    if let path = try? AbsolutePath(validating: url.path) {
      return database(for: path)
    }
    return compdb
  }

  func database(for path: AbsolutePath) -> CompilationDatabase? {
    if compdb == nil {
      var dir = path
      while !dir.isRoot {
        dir = dir.parentDirectory
        if let db = tryLoadCompilationDatabase(directory: dir, fileSystem) {
          compdb = db
          break
        }
      }
    }

    if compdb == nil {
      log("could not open compilation database for \(path)", level: .warning)
    }

    return compdb
  }
}

extension CompilationDatabaseBuildSystem {
  /// Exposed for *testing*.
  public func _settings(for uri: DocumentURI) -> FileBuildSettings? {
    guard let url = uri.fileURL else {
      // We can't determine build settings for non-file URIs.
      return nil
    }
    guard let db = database(for: url),
          let cmd = db[url].first else { return nil }
    return FileBuildSettings(
      compilerArguments: Array(cmd.commandLine.dropFirst()),
      workingDirectory: cmd.directory)
  }
}
