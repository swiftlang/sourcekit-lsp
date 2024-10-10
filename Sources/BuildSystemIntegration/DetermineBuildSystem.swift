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

#if compiler(>=6)
package import LanguageServerProtocol
import SKLogging
package import SKOptions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#else
import LanguageServerProtocol
import SKLogging
import SKOptions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#endif

/// Determine which build system should be started to handle the given workspace folder and at which folder that build
/// system's project root is (see `BuiltInBuildSystem.projectRoot(for:options:)`).
///
/// Returns `nil` if no build system can handle this workspace folder.
package func determineBuildSystem(
  forWorkspaceFolder workspaceFolder: DocumentURI,
  options: SourceKitLSPOptions
) -> BuildSystemKind? {
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
    switch buildSystemType {
    case .buildServer:
      if let projectRoot = ExternalBuildSystemAdapter.projectRoot(for: workspaceFolderPath, options: options) {
        return .buildServer(projectRoot: projectRoot)
      }
    case .compilationDatabase:
      if let projectRoot = CompilationDatabaseBuildSystem.projectRoot(for: workspaceFolderPath, options: options) {
        return .compilationDatabase(projectRoot: projectRoot)
      }
    case .swiftPM:
      if let projectRootURL = SwiftPMBuildSystem.projectRoot(for: workspaceFolderUrl, options: options),
        let projectRoot = try? AbsolutePath(validating: projectRootURL.path)
      {
        return .swiftPM(projectRoot: projectRoot)
      }
    }
  }

  return nil
}
