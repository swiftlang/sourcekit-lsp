//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SKLogging
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

#if compiler(>=6)
package import LanguageServerProtocol
package import SKOptions
#else
import LanguageServerProtocol
import SKOptions
#endif

private func searchForCompilationDatabaseConfig(
  in workspaceFolder: URL,
  options: SourceKitLSPOptions
) -> BuildSystemSpec? {
  let searchPaths =
    (options.compilationDatabaseOrDefault.searchPaths ?? []).compactMap {
      try? RelativePath(validating: $0)
    } + [
      // These default search paths match the behavior of `clangd`
      try! RelativePath(validating: "."),
      try! RelativePath(validating: "build"),
    ]

  return
    searchPaths
    .lazy
    .compactMap { searchPath in
      let path = workspaceFolder.appending(searchPath)

      let jsonPath = path.appendingPathComponent(JSONCompilationDatabaseBuildSystem.dbName)
      if FileManager.default.isFile(at: jsonPath) {
        return BuildSystemSpec(kind: .jsonCompilationDatabase, projectRoot: workspaceFolder, configPath: jsonPath)
      }

      let fixedPath = path.appendingPathComponent(FixedCompilationDatabaseBuildSystem.dbName)
      if FileManager.default.isFile(at: fixedPath) {
        return BuildSystemSpec(kind: .fixedCompilationDatabase, projectRoot: workspaceFolder, configPath: fixedPath)
      }

      return nil
    }
    .first
}

/// Determine which build system should be started to handle the given workspace folder and at which folder that build
/// system's project root is (see `BuiltInBuildSystem.projectRoot(for:options:)`). `onlyConsiderRoot` controls whether
/// paths outside the root should be considered (eg. configuration files in the user's home directory).
///
/// Returns `nil` if no build system can handle this workspace folder.
package func determineBuildSystem(
  forWorkspaceFolder workspaceFolder: DocumentURI,
  onlyConsiderRoot: Bool,
  options: SourceKitLSPOptions,
  hooks: BuildSystemHooks
) -> BuildSystemSpec? {
  if let injectBuildServer = hooks.injectBuildServer {
    return BuildSystemSpec(
      kind: .injected(injectBuildServer),
      projectRoot: workspaceFolder.arbitrarySchemeURL,
      configPath: workspaceFolder.arbitrarySchemeURL
    )
  }

  var buildSystemPreference: [WorkspaceType] = [
    .buildServer, .swiftPM, .compilationDatabase,
  ]
  if let defaultBuildSystem = options.defaultWorkspaceType {
    buildSystemPreference.removeAll(where: { $0 == defaultBuildSystem })
    buildSystemPreference.insert(defaultBuildSystem, at: 0)
  }
  guard let workspaceFolderUrl = workspaceFolder.fileURL else {
    return nil
  }
  for buildSystemType in buildSystemPreference {
    var spec: BuildSystemSpec? = nil

    switch buildSystemType {
    case .buildServer:
      spec = ExternalBuildSystemAdapter.searchForConfig(
        in: workspaceFolderUrl,
        onlyConsiderRoot: onlyConsiderRoot,
        options: options
      )
    case .compilationDatabase:
      spec = searchForCompilationDatabaseConfig(in: workspaceFolderUrl, options: options)
    case .swiftPM:
      #if !NO_SWIFTPM_DEPENDENCY
      spec = SwiftPMBuildSystem.searchForConfig(in: workspaceFolderUrl, options: options)
      #endif
    }

    if let spec {
      return spec
    }
  }

  return nil
}
