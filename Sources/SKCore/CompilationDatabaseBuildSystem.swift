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

import Basic
import LanguageServerProtocol

/// A `BuildSystem` based on loading clang-compatible compilation database(s).
///
/// Provides build settings from a `CompilationDatabase` found by searching a project. For now, only
/// one compilation database, located at the project root.
public final class CompilationDatabaseBuildSystem: BuildSettingsProvider {

  /// The compilation database.
  var compdb: CompilationDatabase? = nil

  let fileSystem: FileSystem

  public init(projectRoot: AbsolutePath? = nil, fileSystem: FileSystem = localFileSystem) {
    self.fileSystem = fileSystem
    if let path = projectRoot {
      self.compdb = tryLoadCompilationDatabase(directory: path, fileSystem: fileSystem)
    }
  }

  public func settings(for url: URL, language: Language) -> FileBuildSettings? {
    guard let db = database(for: url),
          let cmd = db[url].first else { return nil }
    return FileBuildSettings(
      preferredToolchain: nil, // FIXME: infer from path
      compilerArguments: Array(cmd.commandLine.dropFirst()),
      workingDirectory: cmd.directory
    )
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
        if let db = tryLoadCompilationDatabase(directory: dir, fileSystem: fileSystem) {
          compdb = db
          break
        }
      }
    }
    return compdb
  }
}
