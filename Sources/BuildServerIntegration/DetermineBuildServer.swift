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
package import LanguageServerProtocol
import SKLogging
package import SKOptions
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

private func searchForCompilationDatabaseConfig(
  in workspaceFolder: URL,
  options: SourceKitLSPOptions
) -> BuildServerSpec? {
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

      let jsonPath = path.appending(component: JSONCompilationDatabaseBuildServer.dbName)
      if FileManager.default.isFile(at: jsonPath) {
        return BuildServerSpec(kind: .jsonCompilationDatabase, projectRoot: workspaceFolder, configPath: jsonPath)
      }

      let fixedPath = path.appending(component: FixedCompilationDatabaseBuildServer.dbName)
      if FileManager.default.isFile(at: fixedPath) {
        return BuildServerSpec(kind: .fixedCompilationDatabase, projectRoot: workspaceFolder, configPath: fixedPath)
      }

      return nil
    }
    .first
}

/// Determine which build server should be started to handle the given workspace folder and at which folder that build
/// servers's project root is (see `BuiltInBuildServer.projectRoot(for:options:)`). `onlyConsiderRoot` controls whether
/// paths outside the root should be considered (eg. configuration files in the user's home directory).
///
/// Returns `nil` if no build server can handle this workspace folder.
package func determineBuildServer(
  forWorkspaceFolder workspaceFolder: DocumentURI,
  onlyConsiderRoot: Bool,
  options: SourceKitLSPOptions,
  hooks: BuildServerHooks
) -> BuildServerSpec? {
  if let injectBuildServer = hooks.injectBuildServer {
    return BuildServerSpec(
      kind: .injected(injectBuildServer),
      projectRoot: workspaceFolder.arbitrarySchemeURL,
      configPath: workspaceFolder.arbitrarySchemeURL
    )
  }

  var buildServerPreference: [WorkspaceType] = [
    .buildServer, .swiftPM, .compilationDatabase,
  ]
  if let defaultBuildServer = options.defaultWorkspaceType {
    buildServerPreference.removeAll(where: { $0 == defaultBuildServer })
    buildServerPreference.insert(defaultBuildServer, at: 0)
  }
  guard let workspaceFolderUrl = workspaceFolder.fileURL else {
    return nil
  }
  for buildServerType in buildServerPreference {
    var spec: BuildServerSpec? = nil

    switch buildServerType {
    case .buildServer:
      spec = ExternalBuildServerAdapter.searchForConfig(
        in: workspaceFolderUrl,
        onlyConsiderRoot: onlyConsiderRoot,
        options: options
      )
    case .compilationDatabase:
      spec = searchForCompilationDatabaseConfig(in: workspaceFolderUrl, options: options)
    case .swiftPM:
      #if !NO_SWIFTPM_DEPENDENCY
      spec = SwiftPMBuildServer.searchForConfig(in: workspaceFolderUrl, options: options)
      #endif
    }

    if let spec {
      return spec
    }
  }

  return nil
}
