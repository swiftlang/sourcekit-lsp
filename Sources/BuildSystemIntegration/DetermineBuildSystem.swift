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

#if compiler(>=6)
package import LanguageServerProtocol
import SKLogging
package import SKOptions
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#else
import LanguageServerProtocol
import SKLogging
import SKOptions
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#endif

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
  if let workspaceURL = workspaceFolder.fileURL, let buildSystemInjector = hooks.buildSystemInjector {
    return BuildSystemSpec(kind: .injected(buildSystemInjector), projectRoot: workspaceURL, configPath: workspaceURL)
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
      spec = CompilationDatabaseBuildSystem.searchForConfig(in: workspaceFolderUrl, options: options)
    case .swiftPM:
      #if canImport(PackageModel)
      spec = SwiftPMBuildSystem.searchForConfig(in: workspaceFolderUrl, options: options)
      #endif
    }

    if let spec {
      return spec
    }
  }

  return nil
}
