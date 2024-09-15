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
import SKLogging
import SKOptions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

/// An error build systems can throw from `prepare` if they don't support preparation of targets.
package struct PrepareNotSupportedError: Error, CustomStringConvertible {
  package init() {}

  package var description: String { "Preparation not supported" }
}

/// Provider of FileBuildSettings and other build-related information.
///
/// The primary role of the build system is to answer queries for
/// FileBuildSettings and to notify its delegate when they change. The
/// BuildSystem is also the source of related information, such as where the
/// index datastore is located.
///
/// For example, a SwiftPMWorkspace provides compiler arguments for the files
/// contained in a SwiftPM package root directory.
package protocol BuiltInBuildSystem: AnyObject, Sendable {
  /// When opening an LSP workspace at `workspaceFolder`, determine the directory in which a project of this build system
  /// starts. For example, a user might open the `Sources` folder of a SwiftPM project, then the project root is the
  /// directory containing `Package.swift`.
  ///
  /// Returns `nil` if the build system can't handle the given workspace folder
  static func projectRoot(for workspaceFolder: AbsolutePath, options: SourceKitLSPOptions) -> AbsolutePath?

  /// The root of the project that this build system manages. For example, for SwiftPM packages, this is the folder
  /// containing Package.swift. For compilation databases it is the root folder based on which the compilation database
  /// was found.
  var projectRoot: AbsolutePath { get async }

  /// The path to the raw index store data, if any.
  var indexStorePath: AbsolutePath? { get async }

  /// The path to put the index database, if any.
  var indexDatabasePath: AbsolutePath? { get async }

  /// Whether the build system is capable of preparing a target for indexing, ie. if the `prepare` methods has been
  /// implemented.
  var supportsPreparation: Bool { get }

  /// Returns all targets in the build system
  func buildTargets(request: WorkspaceBuildTargetsRequest) async throws -> WorkspaceBuildTargetsResponse

  /// Returns all the source files in the given targets
  func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse

  /// Called when files in the project change.
  func didChangeWatchedFiles(notification: OnWatchedFilesDidChangeNotification) async

  /// Prepare the given targets for indexing and semantic functionality. This should build all swift modules of target
  /// dependencies.
  func prepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse

  /// Retrieve build settings for the given document with the given source
  /// language.
  ///
  /// Returns `nil` if the build system can't provide build settings for this
  /// file or if it hasn't computed build settings for the file yet.
  func sourceKitOptions(
    request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse?

  /// Wait until the build graph has been loaded.
  func waitForUpBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse
}
