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

import BuildSystemIntegration
import LanguageServerProtocol
import SKLogging
import SKOptions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

fileprivate extension WorkspaceType {
  var buildSystemType: BuiltInBuildSystem.Type {
    switch self {
    case .buildServer: return BuildServerBuildSystem.self
    case .compilationDatabase: return CompilationDatabaseBuildSystem.self
    case .swiftPM: return SwiftPMBuildSystem.self
    }
  }
}

/// Determine which build system should be started to handle the given workspace folder and at which folder that build
/// system's project root is (see `BuiltInBuildSystem.projectRoot(for:options:)`).
///
/// Returns `nil` if no build system can handle this workspace folder.
func determineBuildSystem(
  forWorkspaceFolder workspaceFolder: DocumentURI,
  options: SourceKitLSPOptions
) -> (WorkspaceType, projectRoot: AbsolutePath)? {
  var buildSystemPreference: [WorkspaceType] = [
    .buildServer, .swiftPM, .compilationDatabase,
  ]
  if let defaultBuildSystem = options.defaultWorkspaceType {
    buildSystemPreference.removeAll(where: { $0 == defaultBuildSystem })
    buildSystemPreference.insert(defaultBuildSystem, at: 0)
  }
  guard let workspaceFolderUrl = workspaceFolder.fileURL,
    let workspaceFolderPath = try? AbsolutePath(validating: workspaceFolderUrl.path)
  else {
    return nil
  }
  for buildSystemType in buildSystemPreference {
    if let projectRoot = buildSystemType.buildSystemType.projectRoot(for: workspaceFolderPath, options: options) {
      return (buildSystemType, projectRoot)
    }
  }

  return nil
}
