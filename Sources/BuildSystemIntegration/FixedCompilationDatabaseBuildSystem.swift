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

import SKLogging
import SwiftExtensions

#if compiler(>=6)
package import BuildServerProtocol
package import Foundation
package import LanguageServerProtocol
#else
import BuildServerProtocol
import Foundation
import LanguageServerProtocol
#endif

func lastIndexStorePathArgument(in compilerArgs: [String]) -> String? {
  if let indexStorePathIndex = compilerArgs.lastIndex(of: "-index-store-path"),
    indexStorePathIndex + 1 < compilerArgs.count
  {
    return compilerArgs[indexStorePathIndex + 1]
  }
  return nil
}

/// A `BuildSystem` that provides compiler arguments from a `compile_flags.txt` file.
package actor FixedCompilationDatabaseBuildSystem: BuiltInBuildSystem {
  package static let dbName = "compile_flags.txt"

  private let connectionToSourceKitLSP: any Connection

  package let configPath: URL

  /// The compiler arguments from the fixed compilation database.
  ///
  /// Note that this does not contain the path to a compiler.
  var compilerArgs: [String]

  // Watch for all all changes to `compile_flags.txt` and `compile_flags.txt` instead of just the one at
  // `configPath` so that we cover the following semi-common scenario:
  // The user has a build that stores `compile_flags.txt` in `mybuild`. In order to pick it  up, they create a
  // symlink from `<project root>/compile_flags.txt` to `mybuild/compile_flags.txt`.  We want to get notified
  // about the change to `mybuild/compile_flags.txt` because it effectively changes the contents of
  // `<project root>/compile_flags.txt`.
  package let fileWatchers: [FileSystemWatcher] = [
    FileSystemWatcher(globPattern: "**/compile_flags.txt", kind: [.create, .change, .delete])
  ]

  package var indexStorePath: URL? {
    guard let indexStorePath = lastIndexStorePathArgument(in: compilerArgs) else {
      return nil
    }
    return URL(fileURLWithPath: indexStorePath, relativeTo: configPath.deletingLastPathComponent())
  }

  package var indexDatabasePath: URL? {
    indexStorePath?.deletingLastPathComponent().appendingPathComponent("IndexDatabase")
  }

  package nonisolated var supportsPreparationAndOutputPaths: Bool { false }

  private static func parseCompileFlags(at configPath: URL) throws -> [String] {
    let fileContents: String = try String(contentsOf: configPath, encoding: .utf8)

    var compilerArgs: [String] = []
    fileContents.enumerateLines { line, _ in
      compilerArgs.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return compilerArgs
  }

  package init(
    configPath: URL,
    connectionToSourceKitLSP: any Connection
  ) throws {
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
    self.configPath = configPath
    self.compilerArgs = try Self.parseCompileFlags(at: configPath)
  }

  package func buildTargets(request: WorkspaceBuildTargetsRequest) async throws -> WorkspaceBuildTargetsResponse {
    return WorkspaceBuildTargetsResponse(targets: [
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
    return BuildTargetSourcesResponse(items: [
      SourcesItem(
        target: .dummy,
        sources: [SourceItem(uri: URI(configPath.deletingLastPathComponent()), kind: .directory, generated: false)]
      )
    ])
  }

  package func didChangeWatchedFiles(notification: OnWatchedFilesDidChangeNotification) {
    if notification.changes.contains(where: { $0.uri.fileURL?.lastPathComponent == Self.dbName }) {
      self.reloadCompilationDatabase()
    }
  }

  package func prepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    throw ResponseError.methodNotFound(BuildTargetPrepareRequest.method)
  }

  package func buildTargetOutputPaths(
    request: BuildTargetOutputPathsRequest
  ) async throws -> BuildTargetOutputPathsResponse {
    throw ResponseError.methodNotFound(BuildTargetOutputPathsRequest.method)
  }

  package func sourceKitOptions(
    request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    let compilerName: String
    switch request.language {
    case .swift: compilerName = "swiftc"
    case .c, .cpp, .objective_c, .objective_cpp: compilerName = "clang"
    default: return nil
    }
    return TextDocumentSourceKitOptionsResponse(
      compilerArguments: [compilerName] + compilerArgs + [request.textDocument.uri.pseudoPath],
      workingDirectory: try? configPath.deletingLastPathComponent().filePath
    )
  }

  package func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }

  /// The compilation database has been changed on disk.
  /// Reload it and notify the delegate about build setting changes.
  private func reloadCompilationDatabase() {
    orLog("Reloading fixed compilation database") {
      self.compilerArgs = try Self.parseCompileFlags(at: configPath)
      connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
    }
  }
}
