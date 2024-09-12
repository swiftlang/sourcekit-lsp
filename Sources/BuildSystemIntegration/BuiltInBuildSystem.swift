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

package struct SourceFileInfo: Sendable {
  /// The URI of the source file.
  package let uri: DocumentURI

  /// `true` if this file belongs to the root project that the user is working on. It is false, if the file belongs
  /// to a dependency of the project.
  package let isPartOfRootProject: Bool

  /// Whether the file might contain test cases. This property is an over-approximation. It might be true for files
  /// from non-test targets or files that don't actually contain any tests. Keeping this list of files with
  /// `mayContainTets` minimal as possible helps reduce the amount of work that the syntactic test indexer needs to
  /// perform.
  package let mayContainTests: Bool

  package init(uri: DocumentURI, isPartOfRootProject: Bool, mayContainTests: Bool) {
    self.uri = uri
    self.isPartOfRootProject = isPartOfRootProject
    self.mayContainTests = mayContainTests
  }
}

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

  /// Delegate to handle any build system events such as file build settings initial reports as well as changes.
  ///
  /// The build system must not retain the delegate because the delegate can be the `BuildSystemManager`, which could
  /// result in a retain cycle `BuildSystemManager` -> `BuildSystem` -> `BuildSystemManager`.
  var delegate: BuildSystemDelegate? { get async }

  /// Set the build system's delegate.
  ///
  /// - Note: Needed so we can set the delegate from a different actor isolation
  ///   context.
  func setDelegate(_ delegate: BuildSystemDelegate?) async

  /// Whether the build system is capable of preparing a target for indexing, ie. if the `prepare` methods has been
  /// implemented.
  var supportsPreparation: Bool { get }

  /// Returns all targets in the build system
  func buildTargets(request: BuildTargetsRequest) async throws -> BuildTargetsResponse

  /// Returns all the source files in the given targets
  func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse

  /// Called when files in the project change.
  func didChangeWatchedFiles(notification: BuildServerProtocol.DidChangeWatchedFilesNotification) async

  /// Return the list of targets that the given document can be built for.
  func inverseSources(request: InverseSourcesRequest) async throws -> InverseSourcesResponse

  /// Prepare the given targets for indexing and semantic functionality. This should build all swift modules of target
  /// dependencies.
  func prepare(request: PrepareTargetsRequest) async throws -> VoidResponse

  /// Retrieve build settings for the given document with the given source
  /// language.
  ///
  /// Returns `nil` if the build system can't provide build settings for this
  /// file or if it hasn't computed build settings for the file yet.
  func sourceKitOptions(request: SourceKitOptionsRequest) async throws -> SourceKitOptionsResponse?

  /// Schedule a task that re-generates the build graph. The function may return before the build graph has finished
  /// being generated. If clients need to wait for an up-to-date build graph, they should call
  /// `waitForUpToDateBuildGraph` afterwards.
  func scheduleBuildGraphGeneration() async throws

  /// Wait until the build graph has been loaded.
  func waitForUpToDateBuildGraph() async

  /// Sort the targets so that low-level targets occur before high-level targets.
  ///
  /// This sorting is best effort but allows the indexer to prepare and index low-level targets first, which allows
  /// index data to be available earlier.
  ///
  /// `nil` if the build system doesn't support topological sorting of targets.
  func topologicalSort(of targets: [BuildTargetIdentifier]) async -> [BuildTargetIdentifier]?

  /// Returns the list of targets that might depend on the given target and that need to be re-prepared when a file in
  /// `target` is modified.
  ///
  /// The returned list can be an over-approximation, in which case the indexer will perform more work than strictly
  /// necessary by scheduling re-preparation of a target where it isn't necessary.
  ///
  /// Returning `nil` indicates that all targets should be considered depending on the given target.
  func targets(dependingOn targets: [BuildTargetIdentifier]) async -> [BuildTargetIdentifier]?

  /// If the build system has knowledge about the language that this document should be compiled in, return it.
  ///
  /// This is used to determine the language in which a source file should be background indexed.
  ///
  /// If `nil` is returned, the language based on the file's extension.
  func defaultLanguage(for document: DocumentURI) async -> Language?

  /// The toolchain that should be used to open the given document.
  ///
  /// If `nil` is returned, then the default toolchain for the given language is used.
  func toolchain(for uri: DocumentURI, _ language: Language) async -> Toolchain?

  /// Adds a callback that should be called when the value returned by `sourceFiles()` changes.
  ///
  /// The callback might also be called without an actual change to `sourceFiles`.
  func addSourceFilesDidChangeCallback(_ callback: @Sendable @escaping () async -> Void) async
}
