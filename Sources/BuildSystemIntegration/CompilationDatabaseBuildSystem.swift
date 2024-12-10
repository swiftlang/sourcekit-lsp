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

#if compiler(>=6)
package import BuildServerProtocol
import Dispatch
package import Foundation
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
package import SKOptions
import ToolchainRegistry
import TSCExtensions

package import struct TSCBasic.RelativePath
#else
import BuildServerProtocol
import Dispatch
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SKOptions
import ToolchainRegistry
import TSCExtensions

import struct TSCBasic.RelativePath
#endif

fileprivate enum Cachable<Value> {
  case noValue
  case value(Value)

  mutating func get(_ compute: () -> Value) -> Value {
    switch self {
    case .noValue:
      let value = compute()
      self = .value(value)
      return value
    case .value(let value):
      return value
    }
  }

  mutating func reset() {
    self = .noValue
  }
}

/// A `BuildSystem` based on loading clang-compatible compilation database(s).
///
/// Provides build settings from a `CompilationDatabase` found by searching a project. For now, only
/// one compilation database, located at the project root.
package actor CompilationDatabaseBuildSystem: BuiltInBuildSystem {
  static package func projectRoot(for workspaceFolder: URL, options: SourceKitLSPOptions) -> URL? {
    if tryLoadCompilationDatabase(directory: workspaceFolder) != nil {
      return workspaceFolder
    }
    return nil
  }

  /// The compilation database.
  var compdb: CompilationDatabase? = nil {
    didSet {
      // Build settings have changed and thus the index store path might have changed.
      // Recompute it on demand.
      _indexStorePath.reset()
    }
  }

  private let connectionToSourceKitLSP: any Connection
  private let searchPaths: [RelativePath]

  package let projectRoot: URL

  package let fileWatchers: [FileSystemWatcher] = [
    FileSystemWatcher(globPattern: "**/compile_commands.json", kind: [.create, .change, .delete]),
    FileSystemWatcher(globPattern: "**/compile_flags.txt", kind: [.create, .change, .delete]),
  ]

  private var _indexStorePath: Cachable<URL?> = .noValue
  package var indexStorePath: URL? {
    _indexStorePath.get {
      guard let compdb else {
        return nil
      }

      for sourceItem in compdb.sourceItems {
        for command in compdb[sourceItem.uri] {
          let args = command.commandLine
          for i in args.indices.reversed() {
            if args[i] == "-index-store-path" && i + 1 < args.count {
              return URL(fileURLWithPath: args[i + 1])
            }
          }
        }
      }
      return nil
    }
  }

  package var indexDatabasePath: URL? {
    indexStorePath?.deletingLastPathComponent().appendingPathComponent("IndexDatabase")
  }

  package nonisolated var supportsPreparation: Bool { false }

  package init?(
    projectRoot: URL,
    searchPaths: [RelativePath],
    connectionToSourceKitLSP: any Connection
  ) {
    self.projectRoot = projectRoot
    self.searchPaths = searchPaths
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
    if let compdb = tryLoadCompilationDatabase(directory: projectRoot, additionalSearchPaths: searchPaths) {
      self.compdb = compdb
    } else {
      return nil
    }
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
    guard request.targets.contains(.dummy), let compdb else {
      return BuildTargetSourcesResponse(items: [])
    }
    return BuildTargetSourcesResponse(items: [SourcesItem(target: .dummy, sources: compdb.sourceItems)])
  }

  package func didChangeWatchedFiles(notification: OnWatchedFilesDidChangeNotification) {
    if notification.changes.contains(where: { self.fileEventShouldTriggerCompilationDatabaseReload(event: $0) }) {
      self.reloadCompilationDatabase()
    }
  }

  package func prepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    throw PrepareNotSupportedError()
  }

  package func sourceKitOptions(
    request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    guard let compdb, let cmd = compdb[request.textDocument.uri].first else {
      return nil
    }
    return TextDocumentSourceKitOptionsResponse(
      compilerArguments: Array(cmd.commandLine.dropFirst()),
      workingDirectory: cmd.directory
    )
  }

  package func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
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
  private func reloadCompilationDatabase() {
    self.compdb = tryLoadCompilationDatabase(directory: projectRoot, additionalSearchPaths: searchPaths)

    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }
}
