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

import IndexStoreDB
import LSPLogging
import LanguageServerProtocol
import SKCore
import SKSupport
import SemanticIndex

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

/// Same as `??` but allows the right-hand side of the operator to 'await'.
fileprivate func firstNonNil<T>(_ optional: T?, _ defaultValue: @autoclosure () async throws -> T) async rethrows -> T {
  if let optional {
    return optional
  }
  return try await defaultValue()
}

fileprivate func firstNonNil<T>(
  _ optional: T?,
  _ defaultValue: @autoclosure () async throws -> T?
) async rethrows -> T? {
  if let optional {
    return optional
  }
  return try await defaultValue()
}

/// Represents the configuration and state of a project or combination of projects being worked on
/// together.
///
/// In LSP, this represents the per-workspace state that is typically only available after the
/// "initialize" request has been made.
///
/// Typically a workspace is contained in a root directory.
public final class Workspace: Sendable {

  /// The root directory of the workspace.
  public let rootUri: DocumentURI?

  /// Tracks dynamically registered server capabilities as well as the client's capabilities.
  public let capabilityRegistry: CapabilityRegistry

  /// The build system manager to use for documents in this workspace.
  public let buildSystemManager: BuildSystemManager

  /// Build setup
  public let buildSetup: BuildSetup

  /// The source code index, if available.
  ///
  /// Usually a checked index (retrieved using `index(checkedFor:)`) should be used instead of the unchecked index.
  private let _uncheckedIndex: ThreadSafeBox<UncheckedIndex?>

  public var uncheckedIndex: UncheckedIndex? {
    return _uncheckedIndex.value
  }

  /// The index that syntactically scans the workspace for tests.
  let syntacticTestIndex = SyntacticTestIndex()

  /// Documents open in the SourceKitLSPServer. This may include open documents from other workspaces.
  private let documentManager: DocumentManager

  /// Language service for an open document, if available.
  let documentService: ThreadSafeBox<[DocumentURI: LanguageService]> = ThreadSafeBox(initialValue: [:])

  /// The `SemanticIndexManager` that keeps track of whose file's index is up-to-date in the workspace and schedules
  /// indexing and preparation tasks for files with out-of-date index.
  ///
  /// `nil` if background indexing is not enabled.
  let semanticIndexManager: SemanticIndexManager?

  public init(
    documentManager: DocumentManager,
    rootUri: DocumentURI?,
    capabilityRegistry: CapabilityRegistry,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPServer.Options,
    underlyingBuildSystem: BuildSystem?,
    index uncheckedIndex: UncheckedIndex?,
    indexDelegate: SourceKitIndexDelegate?,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>,
    logMessageToIndexLog: @escaping @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void,
    indexTasksWereScheduled: @escaping @Sendable (Int) -> Void,
    indexProgressStatusDidChange: @escaping @Sendable () -> Void
  ) async {
    self.documentManager = documentManager
    self.buildSetup = options.buildSetup
    self.rootUri = rootUri
    self.capabilityRegistry = capabilityRegistry
    self._uncheckedIndex = ThreadSafeBox(initialValue: uncheckedIndex)
    self.buildSystemManager = await BuildSystemManager(
      buildSystem: underlyingBuildSystem,
      fallbackBuildSystem: FallbackBuildSystem(buildSetup: buildSetup),
      mainFilesProvider: uncheckedIndex,
      toolchainRegistry: toolchainRegistry
    )
    if options.experimentalFeatures.contains(.backgroundIndexing),
      let uncheckedIndex,
      await buildSystemManager.supportsPreparation
    {
      self.semanticIndexManager = SemanticIndexManager(
        index: uncheckedIndex,
        buildSystemManager: buildSystemManager,
        testHooks: options.indexTestHooks,
        indexTaskScheduler: indexTaskScheduler,
        logMessageToIndexLog: logMessageToIndexLog,
        indexTasksWereScheduled: indexTasksWereScheduled,
        indexProgressStatusDidChange: indexProgressStatusDidChange
      )
    } else {
      self.semanticIndexManager = nil
    }
    await indexDelegate?.addMainFileChangedCallback { [weak self] in
      await self?.buildSystemManager.mainFilesChanged()
    }
    await underlyingBuildSystem?.addSourceFilesDidChangeCallback { [weak self] in
      guard let self else {
        return
      }
      await self.syntacticTestIndex.listOfTestFilesDidChange(self.buildSystemManager.testFiles())
    }
    // Trigger an initial population of `syntacticTestIndex`.
    await syntacticTestIndex.listOfTestFilesDidChange(buildSystemManager.testFiles())
    if let semanticIndexManager {
      await semanticIndexManager.scheduleBuildGraphGenerationAndBackgroundIndexAllFiles()
    }
  }

  /// Creates a workspace for a given root `URL`, inferring the `ExternalWorkspace` if possible.
  ///
  /// - Parameters:
  ///   - url: The root directory of the workspace, which must be a valid path.
  ///   - clientCapabilities: The client capabilities provided during server initialization.
  ///   - toolchainRegistry: The toolchain registry.
  convenience public init(
    documentManager: DocumentManager,
    rootUri: DocumentURI,
    capabilityRegistry: CapabilityRegistry,
    buildSystem: BuildSystem?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPServer.Options,
    indexOptions: IndexOptions = IndexOptions(),
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>,
    logMessageToIndexLog: @escaping @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void,
    indexTasksWereScheduled: @Sendable @escaping (Int) -> Void,
    indexProgressStatusDidChange: @Sendable @escaping () -> Void
  ) async throws {
    var index: IndexStoreDB? = nil
    var indexDelegate: SourceKitIndexDelegate? = nil

    let indexOptions = options.indexOptions
    if let storePath = await firstNonNil(indexOptions.indexStorePath, await buildSystem?.indexStorePath),
      let dbPath = await firstNonNil(indexOptions.indexDatabasePath, await buildSystem?.indexDatabasePath),
      let libPath = await toolchainRegistry.default?.libIndexStore
    {
      do {
        let lib = try IndexStoreLibrary(dylibPath: libPath.pathString)
        indexDelegate = SourceKitIndexDelegate()
        let prefixMappings =
          await firstNonNil(indexOptions.indexPrefixMappings, await buildSystem?.indexPrefixMappings) ?? []
        index = try IndexStoreDB(
          storePath: storePath.pathString,
          databasePath: dbPath.pathString,
          library: lib,
          delegate: indexDelegate,
          listenToUnitEvents: indexOptions.listenToUnitEvents,
          prefixMappings: prefixMappings.map { PathMapping(original: $0.original, replacement: $0.replacement) }
        )
        logger.debug("opened IndexStoreDB at \(dbPath) with store path \(storePath)")
      } catch {
        logger.error("failed to open IndexStoreDB: \(error.localizedDescription)")
      }
    }

    await self.init(
      documentManager: documentManager,
      rootUri: rootUri,
      capabilityRegistry: capabilityRegistry,
      toolchainRegistry: toolchainRegistry,
      options: options,
      underlyingBuildSystem: buildSystem,
      index: UncheckedIndex(index),
      indexDelegate: indexDelegate,
      indexTaskScheduler: indexTaskScheduler,
      logMessageToIndexLog: logMessageToIndexLog,
      indexTasksWereScheduled: indexTasksWereScheduled,
      indexProgressStatusDidChange: indexProgressStatusDidChange
    )
  }

  /// Returns a `CheckedIndex` that verifies that all the returned entries are up-to-date with the given
  /// `IndexCheckLevel`.
  func index(checkedFor checkLevel: IndexCheckLevel) -> CheckedIndex? {
    return _uncheckedIndex.value?.checked(for: checkLevel)
  }

  /// Write the index to disk.
  ///
  /// After this method is called, the workspace will no longer have an index associated with it. It should only be
  /// called when SourceKit-LSP shuts down.
  func closeIndex() {
    _uncheckedIndex.value = nil
  }

  public func filesDidChange(_ events: [FileEvent]) async {
    await buildSystemManager.filesDidChange(events)
    await syntacticTestIndex.filesDidChange(events)
    await semanticIndexManager?.filesDidChange(events)
  }
}

/// Wrapper around a workspace that isn't being retained.
struct WeakWorkspace {
  weak var value: Workspace?

  init(_ value: Workspace? = nil) {
    self.value = value
  }
}

public struct IndexOptions: Sendable {

  /// Override the index-store-path provided by the build system.
  public var indexStorePath: AbsolutePath?

  /// Override the index-database-path provided by the build system.
  public var indexDatabasePath: AbsolutePath?

  /// Override the index prefix mappings provided by the build system.
  public var indexPrefixMappings: [PathPrefixMapping]?

  /// *For Testing* Whether the index should listen to unit events, or wait for
  /// explicit calls to pollForUnitChangesAndWait().
  public var listenToUnitEvents: Bool

  /// The percentage of the machine's cores that should at most be used for background indexing.
  ///
  /// Setting this to a value < 1 ensures that background indexing doesn't use all CPU resources.
  public var maxCoresPercentageToUseForBackgroundIndexing: Double

  public init(
    indexStorePath: AbsolutePath? = nil,
    indexDatabasePath: AbsolutePath? = nil,
    indexPrefixMappings: [PathPrefixMapping]? = nil,
    listenToUnitEvents: Bool = true,
    maxCoresPercentageToUseForBackgroundIndexing: Double = 1
  ) {
    self.indexStorePath = indexStorePath
    self.indexDatabasePath = indexDatabasePath
    self.indexPrefixMappings = indexPrefixMappings
    self.listenToUnitEvents = listenToUnitEvents
    self.maxCoresPercentageToUseForBackgroundIndexing = maxCoresPercentageToUseForBackgroundIndexing
  }
}
