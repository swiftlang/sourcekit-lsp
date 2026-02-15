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

package import BuildServerIntegration
@_spi(SourceKitLSP) package import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// The logging subsystem that should be used for all index-related logging.
let indexLoggingSubsystem = "org.swift.sourcekit-lsp.indexing"

/// A wrapper around `QueuedTask` that only allows equality comparison and inspection whether the `QueuedTask` is
/// currently executing.
///
/// This way we can store `QueuedTask` in the `inProgress` dictionaries while guaranteeing that whoever created the
/// queued task still has exclusive ownership of the task and can thus control the task's cancellation.
private struct OpaqueQueuedIndexTask: Equatable {
  private let task: QueuedTask<AnyIndexTaskDescription>

  var isExecuting: Bool {
    task.isExecuting
  }

  init(_ task: QueuedTask<AnyIndexTaskDescription>) {
    self.task = task
  }

  static func == (lhs: OpaqueQueuedIndexTask, rhs: OpaqueQueuedIndexTask) -> Bool {
    return lhs.task === rhs.task
  }
}

private struct InProgressIndexStore {
  enum State {
    /// We know that we need to index the file but and are currently gathering all information to create the `indexTask`
    /// that will index it.
    ///
    /// This is needed to avoid the following race: We request indexing of file A. Getting the canonical target for A
    /// takes a bit and before that finishes, we request another index of A. In this case, we don't want to kick off
    /// two tasks to update the index store.
    case creatingIndexTask

    /// We are waiting for preparation of the file's target to be scheduled. The next step is that we wait for
    /// preparation to finish before we can update the index store for this file.
    ///
    /// `preparationTaskID` identifies the preparation task so that we can transition a file's index state to
    /// `updatingIndexStore` when its preparation task has finished.
    ///
    /// `indexTask` is a task that finishes after both preparation and index store update are done. Whoever owns the index
    /// task is still the sole owner of it and responsible for its cancellation.
    case waitingForPreparation(preparationTaskID: UUID, indexTask: Task<Void, Never>)

    /// We have started preparing this file and are waiting for preparation to finish before we can update the index
    /// store for this file.
    ///
    /// `preparationTaskID` identifies the preparation task so that we can transition a file's index state to
    /// `updatingIndexStore` when its preparation task has finished.
    ///
    /// `indexTask` is a task that finishes after both preparation and index store update are done. Whoever owns the index
    /// task is still the sole owner of it and responsible for its cancellation.
    case preparing(preparationTaskID: UUID, indexTask: Task<Void, Never>)

    /// The file's target has been prepared and we are updating the file's index store.
    ///
    /// `updateIndexStoreTask` is the task that updates the index store itself.
    ///
    /// `indexTask` is a task that finishes after both preparation and index store update are done. Whoever owns the index
    /// task is still the sole owner of it and responsible for its cancellation.
    case updatingIndexStore(updateIndexStoreTask: OpaqueQueuedIndexTask, indexTask: Task<Void, Never>)
  }

  var state: State

  /// The modification time of the time of `FileToIndex.sourceFile` at the time that indexing was scheduled. This allows
  /// us to avoid scheduling another indexing operation for the file if the file hasn't been modified since an
  /// in-progress indexing operation was scheduled.
  ///
  /// `nil` if the modification date of the file could not be determined.
  var fileModificationDate: Date?
}

/// The information that's needed to index a file within a given target.
package struct FileIndexInfo: Sendable, Hashable {
  package let file: FileToIndex
  package let language: Language
  package let target: BuildTargetIdentifier
  package let outputPath: OutputPath
}

/// Status of document indexing / target preparation in `inProgressIndexAndPreparationTasks`.
package enum IndexTaskStatus: Comparable {
  case scheduled
  case executing
}

/// The current index status that should be displayed to the editor.
///
/// In reality, these status are not exclusive. Eg. the index might be preparing one target for editor functionality,
/// re-generating the build graph and indexing files at the same time. To avoid showing too many concurrent status
/// messages to the user, we only show the highest priority task.
package enum IndexProgressStatus: Sendable, Equatable {
  case preparingFileForEditorFunctionality
  case generatingBuildGraph
  case indexing(
    preparationTasks: [BuildTargetIdentifier: IndexTaskStatus],
    indexTasks: [FileIndexInfo: IndexTaskStatus]
  )
  case upToDate

  package func merging(with other: IndexProgressStatus) -> IndexProgressStatus {
    switch (self, other) {
    case (_, .preparingFileForEditorFunctionality), (.preparingFileForEditorFunctionality, _):
      return .preparingFileForEditorFunctionality
    case (_, .generatingBuildGraph), (.generatingBuildGraph, _):
      return .generatingBuildGraph
    case (
      .indexing(let selfPreparationTasks, let selfIndexTasks),
      .indexing(let otherPreparationTasks, let otherIndexTasks)
    ):
      return .indexing(
        preparationTasks: selfPreparationTasks.merging(otherPreparationTasks) { max($0, $1) },
        indexTasks: selfIndexTasks.merging(otherIndexTasks) { max($0, $1) }
      )
    case (.indexing, .upToDate): return self
    case (.upToDate, .indexing): return other
    case (.upToDate, .upToDate): return .upToDate
    }
  }
}

/// See `SemanticIndexManager.inProgressPrepareForEditorTask`.
private struct InProgressPrepareForEditorTask {
  /// A unique ID that identifies the preparation task and is used to set
  /// `SemanticIndexManager.inProgressPrepareForEditorTask` to `nil`  when the current in progress task finishes.
  let id: UUID

  /// The document that is being prepared.
  let document: DocumentURI

  /// The task that prepares the document. Should never be awaited and only be used to cancel the task.
  let task: Task<Void, Never>
}

/// The reason why a target is being prepared. This is used to determine the `IndexProgressStatus`.
package enum TargetPreparationPurpose: Comparable {
  /// We are preparing the target so we can index files in it.
  case forIndexing

  /// We are preparing the target to provide semantic functionality in one of its files.
  case forEditorFunctionality
}

/// An entry in `SemanticIndexManager.inProgressPreparationTasks`.
private struct InProgressPreparationTask {
  let task: OpaqueQueuedIndexTask
  let purpose: TargetPreparationPurpose
}

/// Schedules index tasks and keeps track of the index status of files.
package final actor SemanticIndexManager {
  /// The underlying index. This is used to check if the index of a file is already up-to-date, in which case it doesn't
  /// need to be indexed again.
  private let index: UncheckedIndex

  /// The build server manager that is used to get compiler arguments for a file.
  private let buildServerManager: BuildServerManager

  /// How long to wait until we cancel an update indexstore task. This timeout should be long enough that all
  /// `swift-frontend` tasks finish within it. It prevents us from blocking the index if the type checker gets stuck on
  /// an expression for a long time.
  package var updateIndexStoreTimeout: Duration

  private let hooks: IndexHooks

  /// The tasks to generate the build graph (resolving package dependencies, generating the build description,
  /// ...) and to schedule indexing of modified tasks.
  private var buildGraphGenerationTasks: [UUID: Task<Void, Never>] = [:]

  /// Tasks that were  created from `workspace/didChangeWatchedFiles` or `buildTarget/didChange` notifications. Needed
  /// so that we can wait for these tasks to be handled in the poll index request.
  private var fileOrBuildTargetChangedTasks: [UUID: Task<Void, Never>] = [:]

  private let preparationUpToDateTracker = UpToDateTracker<BuildTargetIdentifier, DummySecondaryKey>()

  private let indexStoreUpToDateTracker = UpToDateTracker<DocumentURI, BuildTargetIdentifier>()

  /// The preparation tasks that have been started and are either scheduled in the task scheduler or currently
  /// executing.
  ///
  /// After a preparation task finishes, it is removed from this dictionary.
  private var inProgressPreparationTasks: [BuildTargetIdentifier: InProgressPreparationTask] = [:]

  /// The files that are currently being index, either waiting for their target to be prepared, waiting for the index
  /// store update task to be scheduled in the task scheduler or which currently have an index store update running.
  ///
  /// After the file is indexed, it is removed from this dictionary.
  private var inProgressIndexTasks: [FileIndexInfo: InProgressIndexStore] = [:]

  /// The currently running task that prepares a document for editor functionality.
  ///
  /// This is used so we can cancel preparation tasks for documents that the user is no longer interacting with and
  /// avoid the following scenario: The user browses through documents from targets A, B, and C in quick succession. We
  /// don't want stack preparation of A, B, and C. Instead we want to only prepare target C - and also finish
  /// preparation of A if it has already started when the user opens C.
  private var inProgressPrepareForEditorTask: InProgressPrepareForEditorTask? = nil

  /// The `TaskScheduler` that manages the scheduling of index tasks. This is shared among all `SemanticIndexManager`s
  /// in the process, to ensure that we don't schedule more index operations than processor cores from multiple
  /// workspaces.
  private let indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>

  /// Callback that is called when an indexing task produces output it wants to log to the index log.
  private let logMessageToIndexLog:
    @Sendable (
      _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
    ) -> Void

  /// Called when files are scheduled to be indexed.
  ///
  /// The parameter is the number of files that were scheduled to be indexed.
  private let indexTasksWereScheduled: @Sendable (_ numberOfFileScheduled: Int) -> Void

  /// The size of the batches in which the `SemanticIndexManager` should dispatch preparation tasks.
  private let preparationBatchingStrategy: PreparationBatchingStrategy?

  /// Callback that is called when `progressStatus` might have changed.
  private let indexProgressStatusDidChange: @Sendable () -> Void

  // MARK: - Public API

  /// A summary of the tasks that this `SemanticIndexManager` has currently scheduled or is currently indexing.
  package var progressStatus: IndexProgressStatus {
    if inProgressPreparationTasks.values.contains(where: { $0.purpose == .forEditorFunctionality }) {
      return .preparingFileForEditorFunctionality
    }
    let preparationTasks = inProgressPreparationTasks.mapValues { inProgressTask in
      return inProgressTask.task.isExecuting ? IndexTaskStatus.executing : IndexTaskStatus.scheduled
    }
    let indexTasks = inProgressIndexTasks.mapValues { inProgress in
      switch inProgress.state {
      case .creatingIndexTask, .waitingForPreparation, .preparing:
        return IndexTaskStatus.scheduled
      case .updatingIndexStore(let updateIndexStoreTask, indexTask: _):
        return updateIndexStoreTask.isExecuting ? IndexTaskStatus.executing : IndexTaskStatus.scheduled
      }
    }
    if !preparationTasks.isEmpty || !indexTasks.isEmpty {
      return .indexing(preparationTasks: preparationTasks, indexTasks: indexTasks)
    }
    // Only report the `schedulingIndexing` status when we don't have any in-progress indexing tasks. This way we avoid
    // flickering between indexing progress and `Scheduling indexing` if we trigger an index schedule task while
    // indexing is already in progress
    if !buildGraphGenerationTasks.isEmpty {
      return .generatingBuildGraph
    }
    return .upToDate
  }

  package init(
    index: UncheckedIndex,
    buildServerManager: BuildServerManager,
    updateIndexStoreTimeout: Duration,
    hooks: IndexHooks,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>,
    preparationBatchingStrategy: PreparationBatchingStrategy?,
    logMessageToIndexLog:
      @escaping @Sendable (
        _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
      ) -> Void,
    indexTasksWereScheduled: @escaping @Sendable (Int) -> Void,
    indexProgressStatusDidChange: @escaping @Sendable () -> Void
  ) {
    self.index = index
    self.buildServerManager = buildServerManager
    self.updateIndexStoreTimeout = updateIndexStoreTimeout
    self.hooks = hooks
    self.indexTaskScheduler = indexTaskScheduler
    self.preparationBatchingStrategy = preparationBatchingStrategy
    self.logMessageToIndexLog = logMessageToIndexLog
    self.indexTasksWereScheduled = indexTasksWereScheduled
    self.indexProgressStatusDidChange = indexProgressStatusDidChange
  }

  /// Regenerate the build graph (also resolving package dependencies) and then index all the source files known to the
  /// build server that don't currently have a unit with a timestamp that matches the mtime of the file.
  ///
  /// This is a costly operation since it iterates through all the unit files on the file
  /// system but if existing unit files are not known to the index, we might re-index those files even if they are
  /// up-to-date. Generally this should be set to `true` during the initial indexing (in which case we might be need to
  /// build the indexstore-db) and `false` for all subsequent indexing.
  package func scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(indexFilesWithUpToDateUnit: Bool) async {
    let taskId = UUID()
    let generateBuildGraphTask = Task(priority: .low) {
      await withLoggingSubsystemAndScope(subsystem: indexLoggingSubsystem, scope: "build-graph-generation") {
        await hooks.buildGraphGenerationDidStart?()
        await self.buildServerManager.waitForUpToDateBuildGraph()
        // Polling for unit changes is a costly operation since it iterates through all the unit files on the file
        // system but if existing unit files are not known to the index, we might re-index those files even if they are
        // up-to-date. This operation is worth the cost during initial indexing and during the manual re-index command.
        index.pollForUnitChangesAndWait()
        await hooks.buildGraphGenerationDidFinish?()
        // TODO: Ideally this would be a type like any Collection<DocumentURI> & Sendable but that doesn't work due to
        // https://github.com/swiftlang/swift/issues/75602
        let filesToIndex: [DocumentURI] =
          await orLog("Getting files to index") {
            try await self.buildServerManager.buildableSourceFiles().sorted { $0.stringValue < $1.stringValue }
          } ?? []
        await self.scheduleIndexing(
          of: filesToIndex,
          waitForBuildGraphGenerationTasks: false,
          indexFilesWithUpToDateUnit: indexFilesWithUpToDateUnit,
          priority: .low
        )
        buildGraphGenerationTasks[taskId] = nil
      }
    }
    buildGraphGenerationTasks[taskId] = generateBuildGraphTask
    indexProgressStatusDidChange()
  }

  /// Causes all files to be re-indexed even if the unit file for the source file is up to date.
  /// See `TriggerReindexRequest`.
  package func scheduleReindex() async {
    await indexStoreUpToDateTracker.markAllKnownOutOfDate()
    await preparationUpToDateTracker.markAllKnownOutOfDate()
    await scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(indexFilesWithUpToDateUnit: true)
  }

  private func waitForBuildGraphGenerationTasks() async {
    await buildGraphGenerationTasks.values.concurrentForEach { await $0.value }
  }

  /// Wait for all in-progress index tasks to finish.
  package func waitForUpToDateIndex() async {
    logger.info("Waiting for up-to-date index")
    // Wait for a build graph update first, if one is in progress. This will add all index tasks to `indexStatus`, so we
    // can await the index tasks below.
    await waitForBuildGraphGenerationTasks()

    await fileOrBuildTargetChangedTasks.concurrentForEach { await $0.value.value }

    await inProgressIndexTasks.concurrentForEach { (_, inProgress) in
      switch inProgress.state {
      case .creatingIndexTask:
        break
      case .waitingForPreparation(preparationTaskID: _, let indexTask),
        .preparing(preparationTaskID: _, let indexTask),
        .updatingIndexStore(updateIndexStoreTask: _, let indexTask):
        await indexTask.value
      }
    }
    index.pollForUnitChangesAndWait()
    logger.debug("Done waiting for up-to-date index")
  }

  /// Ensure that the index for the given files is up-to-date.
  ///
  /// This tries to produce an up-to-date index for the given files as quickly as possible. To achieve this, it might
  /// suspend previous target-wide index tasks in favor of index tasks that index a fewer files.
  package func waitForUpToDateIndex(for uris: some Collection<DocumentURI> & Sendable) async {
    logger.info(
      "Waiting for up-to-date index for \(uris.map { $0.fileURL?.lastPathComponent ?? $0.stringValue }.joined(separator: ", "))"
    )

    // Create a new index task for the files that aren't up-to-date. The newly scheduled index tasks will
    // - Wait for the existing index operations to finish if they have the same number of files.
    // - Reschedule the background index task in favor of an index task with fewer source files.
    await self.scheduleIndexing(
      of: uris,
      waitForBuildGraphGenerationTasks: true,
      indexFilesWithUpToDateUnit: false,
      priority: nil
    ).value
    index.pollForUnitChangesAndWait()
    logger.debug("Done waiting for up-to-date index")
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    // We only re-index the files that were changed and don't re-index any of their dependencies. See the
    // `Documentation/Files_To_Reindex.md` file.
    let changedFiles = events.filter { $0.type != .deleted }.map(\.uri)
    await indexStoreUpToDateTracker.markOutOfDate(changedFiles)

    var outOfDateTargets = Set<BuildTargetIdentifier>()
    var targetsOfChangedFiles = Set<BuildTargetIdentifier>()
    for file in changedFiles {
      let changedTargets = await buildServerManager.targets(for: file)
      targetsOfChangedFiles.formUnion(changedTargets)
      if Language(inferredFromFileExtension: file) == nil {
        // Preparation tracking should be per file. For now consider any non-known-language change as having to
        // re-prepare the target itself so that we re-prepare potential input files to plugins.
        // https://github.com/swiftlang/sourcekit-lsp/issues/1975
        outOfDateTargets.formUnion(changedTargets)
      }
    }
    outOfDateTargets.formUnion(await buildServerManager.targets(dependingOn: targetsOfChangedFiles))
    if !outOfDateTargets.isEmpty {
      logger.info(
        """
        Marking dependent targets as out-of-date: \
        \(String(outOfDateTargets.map(\.uri.stringValue).joined(separator: ", ")))
        """
      )
      await preparationUpToDateTracker.markOutOfDate(outOfDateTargets)
    }

    // We need to invalidate the preparation status of the changed files immediately so that we re-prepare its target
    // eg. on a `workspace/sourceKitOptions` request. But the actual indexing can happen using a background task.
    // We don't need a queue here because we don't care about the order in which we schedule re-indexing of files.
    let uuid = UUID()
    fileOrBuildTargetChangedTasks[uuid] = Task {
      defer { fileOrBuildTargetChangedTasks[uuid] = nil }
      await scheduleIndexing(
        of: changedFiles,
        waitForBuildGraphGenerationTasks: true,
        indexFilesWithUpToDateUnit: false,
        priority: .low
      )
    }
  }

  package func buildTargetsChanged(_ targets: Set<BuildTargetIdentifier>?) async {
    if let targets {
      var targetsAndDependencies = targets
      targetsAndDependencies.formUnion(await buildServerManager.targets(dependingOn: targets))
      if !targetsAndDependencies.isEmpty {
        logger.info(
          """
          Marking dependent targets as out-of-date: \
          \(String(targetsAndDependencies.map(\.uri.stringValue).joined(separator: ", ")))
          """
        )
        await preparationUpToDateTracker.markOutOfDate(targetsAndDependencies)
      }
    } else {
      await preparationUpToDateTracker.markAllKnownOutOfDate()
    }

    // We need to invalidate the preparation status of the changed files immediately so that we re-prepare its target
    // eg. on a `workspace/sourceKitOptions` request. But the actual indexing can happen using a background task.
    // We don't need a queue here because we don't care about the order in which we schedule re-indexing of files.
    let uuid = UUID()
    fileOrBuildTargetChangedTasks[uuid] = Task {
      await orLog("Scheduling re-indexing of changed targets") {
        defer { fileOrBuildTargetChangedTasks[uuid] = nil }
        var sourceFiles = try await self.buildServerManager.sourceFiles(includeNonBuildableFiles: false)
        if let targets {
          sourceFiles = sourceFiles.filter { !targets.isDisjoint(with: $0.value.targets) }
        }
        _ = await scheduleIndexing(
          of: sourceFiles.keys,
          waitForBuildGraphGenerationTasks: true,
          indexFilesWithUpToDateUnit: false,
          priority: .low
        )
      }
    }
  }

  /// Returns the files that should be indexed to get up-to-date index information for the given files.
  ///
  /// If `files` contains a header file, this will return a `FileToIndex` that re-indexes a main file which includes the
  /// header file to update the header file's index.
  ///
  /// The returned results will not include files that are known to be up-to-date based on `indexStoreUpToDateTracker`
  /// or the unit timestamp will not be re-indexed unless `indexFilesWithUpToDateUnit` is `true`.
  private func filesToIndex(
    toCover files: some Collection<DocumentURI> & Sendable,
    indexFilesWithUpToDateUnits: Bool
  ) async -> [(file: FileIndexInfo, fileModificationDate: Date?)] {
    let sourceFiles = await orLog("Getting source files in project") {
      try await buildServerManager.buildableSourceFiles()
    }
    guard let sourceFiles else {
      return []
    }
    let modifiedFilesIndex = index.checked(for: .modifiedFiles)

    var filesToReIndex: [(FileIndexInfo, Date?)] = []
    for uri in files {
      var didFindTargetToIndex = false
      for (target, outputPath) in await buildServerManager.sourceFileInfo(for: uri)?.targetsToOutputPath ?? [:] {
        // First, check if we know that the file is up-to-date, in which case we don't need to hit the index or file
        // system at all
        if !indexFilesWithUpToDateUnits, await indexStoreUpToDateTracker.isUpToDate(uri, target) {
          continue
        }
        if sourceFiles.contains(uri) {
          guard let outputPath else {
            logger.info("Not indexing \(uri.forLogging) because its output file could not be determined")
            continue
          }
          let hasUpToDateUnit =
            orLog("Checking if modified file has up-to-date unit") {
              try modifiedFilesIndex.hasUpToDateUnit(for: uri, outputPath: outputPath)
            } ?? true
          if !indexFilesWithUpToDateUnits, hasUpToDateUnit {
            continue
          }
          // If this is a source file, just index it.
          guard let language = await buildServerManager.defaultLanguage(for: uri, in: target) else {
            continue
          }
          didFindTargetToIndex = true
          filesToReIndex.append(
            (
              FileIndexInfo(file: .indexableFile(uri), language: language, target: target, outputPath: outputPath),
              modifiedFilesIndex.modificationDate(of: uri)
            )
          )
        }
      }
      if didFindTargetToIndex {
        continue
      }
      // If we haven't found any ways to index the file, see if it is a header file. If so, index a main file that
      // that imports it to update header file's index.
      // Deterministically pick a main file. This ensures that we always pick the same main file for a header. This way,
      // if we request the same header to be indexed twice, we'll pick the same unit file the second time around,
      // realize that its timestamp is later than the modification date of the header and we don't need to re-index.
      let mainFile = await buildServerManager.mainFiles(containing: uri)
        .filter { sourceFiles.contains($0) }
        .sorted(by: { $0.stringValue < $1.stringValue }).first
      guard let mainFile else {
        logger.info("Not indexing \(uri.forLogging) because its main file could not be inferred")
        continue
      }
      let targetAndOutputPath = (await buildServerManager.sourceFileInfo(for: mainFile)?.targetsToOutputPath ?? [:])
        .sorted(by: { $0.key.uri.stringValue < $1.key.uri.stringValue }).first
      guard let targetAndOutputPath else {
        logger.info(
          "Not indexing \(uri.forLogging) because the target file of its main file \(mainFile.forLogging) could not be determined"
        )
        continue
      }
      guard let outputPath = targetAndOutputPath.value else {
        logger.info(
          "Not indexing \(uri.forLogging) because the output file of its main file \(mainFile.forLogging) could not be determined"
        )
        continue
      }
      let hasUpToDateUnit =
        orLog("Checking if modified file has up-to-date unit") {
          try modifiedFilesIndex.hasUpToDateUnit(for: uri, mainFile: mainFile, outputPath: outputPath)
        } ?? true
      if !indexFilesWithUpToDateUnits, hasUpToDateUnit {
        continue
      }
      guard let language = await buildServerManager.defaultLanguage(for: uri, in: targetAndOutputPath.key) else {
        continue
      }
      filesToReIndex.append(
        (
          FileIndexInfo(
            file: .headerFile(header: uri, mainFile: mainFile),
            language: language,
            target: targetAndOutputPath.key,
            outputPath: outputPath
          ),
          modifiedFilesIndex.modificationDate(of: uri)
        )
      )
    }
    return filesToReIndex
  }

  /// Schedule preparation of the target that contains the given URI, building all modules that the file depends on.
  ///
  /// This is intended to be called when the user is interacting with the document at the given URI.
  package func schedulePreparationForEditorFunctionality(of uri: DocumentURI, priority: TaskPriority? = nil) {
    if inProgressPrepareForEditorTask?.document == uri {
      // We are already preparing this document, so nothing to do. This is necessary to avoid the following scenario:
      // Determining the canonical target for a document takes 1s and we get a new document request for the
      // document ever 0.5s, which would cancel the previous in-progress preparation task, cancelling the canonical
      // target configuration, never actually getting to the actual preparation.
      return
    }
    let id = UUID()
    let task = Task(priority: priority) {
      await withLoggingScope("preparation") {
        await prepareFileForEditorFunctionality(uri)
        if inProgressPrepareForEditorTask?.id == id {
          inProgressPrepareForEditorTask = nil
          self.indexProgressStatusDidChange()
        }
      }
    }

    markPreparationForEditorFunctionalityTaskAsIrrelevant()
    inProgressPrepareForEditorTask = InProgressPrepareForEditorTask(
      id: id,
      document: uri,
      task: task
    )
    self.indexProgressStatusDidChange()
  }

  /// If there is an in-progress prepare for editor task, cancel it to indicate that we are no longer interested in it.
  /// This will cancel the preparation of `inProgressPrepareForEditorTask`'s target if it hasn't started yet. If the
  /// preparation has already started, we don't cancel it to guarantee forward progress (see comment at the end of
  /// `SemanticIndexManager.prepare`).
  package func markPreparationForEditorFunctionalityTaskAsIrrelevant() {
    guard let inProgressPrepareForEditorTask else {
      return
    }
    logger.debug("Marking preparation of \(inProgressPrepareForEditorTask.document) as no longer relevant")
    inProgressPrepareForEditorTask.task.cancel()
  }

  /// Prepare the target that the given file is in, building all modules that the file depends on. Returns when
  /// preparation has finished.
  ///
  /// If file's target is known to be up-to-date, this returns almost immediately.
  package func prepareFileForEditorFunctionality(_ uri: DocumentURI) async {
    guard let target = await buildServerManager.canonicalTarget(for: uri) else {
      return
    }
    if Task.isCancelled {
      return
    }
    if await preparationUpToDateTracker.isUpToDate(target) {
      // If the target is up-to-date, there is nothing to prepare.
      return
    }
    await self.prepare(targets: [target], purpose: .forEditorFunctionality, priority: nil)
  }

  /// Prepare the given target.
  ///
  /// Returns `false` if the target was already up-to-date and `true` if this did actually cause the target to ger
  /// prepared.
  package func prepareTargetsForSourceKitOptions(target: BuildTargetIdentifier) async -> Bool {
    if await preparationUpToDateTracker.isUpToDate(target) {
      return false
    }
    await self.prepare(targets: [target], purpose: .forEditorFunctionality, priority: nil)
    return true
  }

  // MARK: - Helper functions

  private func schedulePreparation(
    targets: [BuildTargetIdentifier],
    purpose: TargetPreparationPurpose,
    priority: TaskPriority?,
    executionStatusChangedCallback: @escaping (QueuedTask<AnyIndexTaskDescription>, TaskExecutionState) async -> Void
  ) async -> QueuedTask<AnyIndexTaskDescription>? {
    // Perform a quick initial check whether the target is up-to-date, in which case we don't need to schedule a
    // preparation operation at all.
    // We will check the up-to-date status again in `PreparationTaskDescription.execute`. This ensures that if we
    // schedule two preparations of the same target in quick succession, only the first one actually performs a prepare
    // and the second one will be a no-op once it runs.
    let targetsToPrepare = await targets.asyncFilter {
      await !preparationUpToDateTracker.isUpToDate($0)
    }

    guard !targetsToPrepare.isEmpty else {
      return nil
    }

    let taskDescription = AnyIndexTaskDescription(
      PreparationTaskDescription(
        targetsToPrepare: targetsToPrepare,
        buildServerManager: self.buildServerManager,
        preparationUpToDateTracker: preparationUpToDateTracker,
        logMessageToIndexLog: logMessageToIndexLog,
        hooks: hooks,
        purpose: purpose
      )
    )
    if Task.isCancelled {
      return nil
    }
    let preparationTask = await indexTaskScheduler.schedule(priority: priority, taskDescription) { task, newState in
      await executionStatusChangedCallback(task, newState)
      guard case .finished = newState else {
        self.indexProgressStatusDidChange()
        return
      }
      for target in targetsToPrepare {
        if self.inProgressPreparationTasks[target]?.task == OpaqueQueuedIndexTask(task) {
          self.inProgressPreparationTasks[target] = nil
        }
      }
      self.indexProgressStatusDidChange()
    }
    for target in targetsToPrepare {
      // If we are preparing the same target for indexing and editor functionality, pick editor functionality as the
      // purpose because it is more significant.
      let mergedPurpose =
        if let existingPurpose = inProgressPreparationTasks[target]?.purpose {
          max(existingPurpose, purpose)
        } else {
          purpose
        }
      inProgressPreparationTasks[target] = InProgressPreparationTask(
        task: OpaqueQueuedIndexTask(preparationTask),
        purpose: mergedPurpose
      )
    }
    return preparationTask
  }

  private func prepare(
    targets: [BuildTargetIdentifier],
    purpose: TargetPreparationPurpose,
    priority: TaskPriority?,
    executionStatusChangedCallback: @escaping (QueuedTask<AnyIndexTaskDescription>, TaskExecutionState) async -> Void =
      { _, _ in }
  ) async {
    let preparationTask = await schedulePreparation(
      targets: targets,
      purpose: purpose,
      priority: priority,
      executionStatusChangedCallback: executionStatusChangedCallback
    )
    guard let preparationTask else {
      return
    }
    await withTaskCancellationHandler {
      return await preparationTask.waitToFinish()
    } onCancel: {
      // Only cancel the preparation task if it hasn't started executing yet. This ensures that we always make progress
      // during preparation and can't get into the following scenario: The user has two target A and B that both take
      // 10s to prepare. The user is now switching between the files every 5 seconds, which would always cause
      // preparation for one target to get cancelled, never resulting in an up-to-date preparation status.
      if !preparationTask.isExecuting {
        preparationTask.cancel()
      }
    }
  }

  /// Update the index store for the given files, assuming that their targets has already been prepared.
  private func updateIndexStore(
    for fileAndOutputPaths: [FileAndOutputPath],
    target: BuildTargetIdentifier,
    language: Language,
    indexFilesWithUpToDateUnit: Bool,
    preparationTaskID: UUID,
    priority: TaskPriority?
  ) async {
    let taskDescription = AnyIndexTaskDescription(
      UpdateIndexStoreTaskDescription(
        filesToIndex: fileAndOutputPaths,
        target: target,
        language: language,
        buildServerManager: self.buildServerManager,
        index: index,
        indexStoreUpToDateTracker: indexStoreUpToDateTracker,
        indexFilesWithUpToDateUnit: indexFilesWithUpToDateUnit,
        logMessageToIndexLog: logMessageToIndexLog,
        timeout: updateIndexStoreTimeout,
        hooks: hooks
      )
    )

    let updateIndexTask = await indexTaskScheduler.schedule(priority: priority, taskDescription) { task, newState in
      guard case .finished = newState else {
        self.indexProgressStatusDidChange()
        return
      }
      for fileAndOutputPath in fileAndOutputPaths {
        let fileAndTarget = FileIndexInfo(
          file: fileAndOutputPath.file,
          language: language,
          target: target,
          outputPath: fileAndOutputPath.outputPath
        )
        switch self.inProgressIndexTasks[fileAndTarget]?.state {
        case .updatingIndexStore(let registeredTask, _):
          if registeredTask == OpaqueQueuedIndexTask(task) {
            self.inProgressIndexTasks[fileAndTarget] = nil
          }
        case .waitingForPreparation(let registeredTask, _), .preparing(let registeredTask, _):
          if registeredTask == preparationTaskID {
            self.inProgressIndexTasks[fileAndTarget] = nil
          }
        case .creatingIndexTask, nil:
          break
        }
      }
      self.indexProgressStatusDidChange()
    }
    for fileAndOutputPath in fileAndOutputPaths {
      let fileAndTarget = FileIndexInfo(
        file: fileAndOutputPath.file,
        language: language,
        target: target,
        outputPath: fileAndOutputPath.outputPath
      )
      switch inProgressIndexTasks[fileAndTarget]?.state {
      case .waitingForPreparation(preparationTaskID, let indexTask), .preparing(preparationTaskID, let indexTask):
        inProgressIndexTasks[fileAndTarget]?.state = .updatingIndexStore(
          updateIndexStoreTask: OpaqueQueuedIndexTask(updateIndexTask),
          indexTask: indexTask
        )
      default: break
      }
    }
    return await updateIndexTask.waitToFinishPropagatingCancellation()
  }

  /// Index the given set of files at the given priority, preparing their targets beforehand, if needed. Files that are
  /// known to be up-to-date based on `indexStoreUpToDateTracker` or the unit timestamp will not be re-indexed unless
  /// `indexFilesWithUpToDateUnit` is `true`.
  ///
  /// If `waitForBuildGraphGenerationTasks` is `true` and there are any tasks in progress that wait for an up-to-date
  /// build graph, wait for those to finish. This is helpful so to avoid the following: We receive a build target change
  /// notification before the initial background indexing has finished. If indexstore-db hasn't been initialized with
  /// `pollForUnitChangesAndWait` yet, we might not know that the changed targets' files' index is actually up-to-date
  /// and would thus schedule an unnecessary re-index of the file.
  ///
  /// The returned task finishes when all files are indexed.
  @discardableResult
  package func scheduleIndexing(
    of files: some Collection<DocumentURI> & Sendable,
    waitForBuildGraphGenerationTasks: Bool,
    indexFilesWithUpToDateUnit: Bool,
    priority: TaskPriority?
  ) async -> Task<Void, Never> {
    if waitForBuildGraphGenerationTasks {
      await self.waitForBuildGraphGenerationTasks()
    }
    // Perform a quick initial check to whether the files is up-to-date, in which case we don't need to schedule a
    // prepare and index operation at all.
    // We will check the up-to-date status again in `IndexTaskDescription.execute`. This ensures that if we schedule
    // schedule two indexing jobs for the same file in quick succession, only the first one actually updates the index
    // store and the second one will be a no-op once it runs.
    var filesToIndex = await filesToIndex(toCover: files, indexFilesWithUpToDateUnits: indexFilesWithUpToDateUnit)
      // sort files to get deterministic indexing order
      .sorted(by: {
        if $0.file.file.sourceFile.stringValue != $1.file.file.sourceFile.stringValue {
          return $0.file.file.sourceFile.stringValue < $1.file.file.sourceFile.stringValue
        }
        return $0.file.target.uri.stringValue < $1.file.target.uri.stringValue
      })

    filesToIndex =
      filesToIndex
      .filter { file in
        let inProgress = inProgressIndexTasks[file.file]

        switch inProgress?.state {
        case nil:
          return true
        case .creatingIndexTask, .waitingForPreparation:
          // We already have a task that indexes the file but hasn't started preparation yet. Indexing the file again
          // won't produce any new results.
          return false
        case .preparing(_, _), .updatingIndexStore(_, _):
          // We have started indexing of the file and are now requesting to index it again. Unless we know that the file
          // hasn't been modified since the last request for indexing, we need to schedule it to get re-indexed again.
          if let modDate = file.fileModificationDate, inProgress?.fileModificationDate == modDate {
            return false
          } else {
            return true
          }
        }
      }

    if filesToIndex.isEmpty {
      indexProgressStatusDidChange()
      // Early exit if there are no files to index.
      return Task {}
    }

    logger.debug(
      "Scheduling indexing of \(filesToIndex.map(\.file.file.sourceFile.stringValue).joined(separator: ", "))"
    )

    // Sort the targets in topological order so that low-level targets get built before high-level targets, allowing us
    // to index the low-level targets ASAP.
    var filesByTarget: [BuildTargetIdentifier: [FileIndexInfo]] = [:]

    // The number of index tasks that don't currently have an in-progress task associated with it.
    // The denominator in the index progress should get incremented by this amount.
    // We don't want to increment the denominator for tasks that already have an index in progress.
    var newIndexTasks = 0

    for (fileIndexInfo, fileModificationDate) in filesToIndex {
      guard UpdateIndexStoreTaskDescription.canIndex(language: fileIndexInfo.language) else {
        continue
      }

      if inProgressIndexTasks[fileIndexInfo] == nil {
        // If `inProgressIndexTasks[fileToIndex]` is not `nil`, this new index task is replacing another index task.
        // We are thus not indexing a new file and thus shouldn't increment the denominator of the indexing status.
        newIndexTasks += 1
      }
      inProgressIndexTasks[fileIndexInfo] = InProgressIndexStore(
        state: .creatingIndexTask,
        fileModificationDate: fileModificationDate
      )

      filesByTarget[fileIndexInfo.target, default: []].append(fileIndexInfo)
    }
    if newIndexTasks > 0 {
      indexTasksWereScheduled(newIndexTasks)
    }

    // The targets sorted in reverse topological order, low-level targets before high-level targets. If topological
    // sorting fails, sorted in another deterministic way where the actual order doesn't matter.
    var sortedTargets: [BuildTargetIdentifier] =
      await orLog("Sorting targets") { try await buildServerManager.topologicalSort(of: Array(filesByTarget.keys)) }
      ?? Array(filesByTarget.keys).sorted { $0.uri.stringValue < $1.uri.stringValue }

    if Set(sortedTargets) != Set(filesByTarget.keys) {
      logger.fault(
        """
        Sorting targets topologically changed set of targets:
        \(sortedTargets.map(\.uri.stringValue).joined(separator: ", ")) != \(filesByTarget.keys.map(\.uri.stringValue).joined(separator: ", "))
        """
      )
      sortedTargets = Array(filesByTarget.keys).sorted { $0.uri.stringValue < $1.uri.stringValue }
    }

    var indexTasks: [Task<Void, Never>] = []

    // TODO: When we can index multiple targets concurrently in SwiftPM, increase the batch size to half the
    // processor count, so we can get parallelism during preparation.
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1262)
    let batchSize: Int
    switch preparationBatchingStrategy {
    case .fixedTargetBatchSize(let size):
      batchSize = max(size, 1)
    case nil:
      batchSize = 1  // Default: prepare 1 target at a time
    }
    let partitionedTargets = sortedTargets.partition(intoBatchesOfSize: batchSize)

    for targetsBatch in partitionedTargets {
      let preparationTaskID = UUID()
      let filesToIndex = targetsBatch.flatMap { (target) -> [FileIndexInfo] in
        guard let files = filesByTarget[target] else {
          logger.fault("Unexpectedly found no files for target in target batch")
          return []
        }
        return files
      }

      // First schedule preparation of the targets. We schedule the preparation outside of `indexTask` so that we
      // deterministically prepare targets in the topological order for indexing. If we triggered preparation inside the
      // indexTask, we would get nondeterministic ordering since Tasks may start executing in any order.
      let preparationTask = await schedulePreparation(
        targets: targetsBatch,
        purpose: .forIndexing,
        priority: priority
      ) { task, newState in
        if case .executing = newState {
          for file in filesToIndex {
            if case .waitingForPreparation(preparationTaskID: preparationTaskID, indexTask: let indexTask) =
              self.inProgressIndexTasks[file]?.state
            {
              self.inProgressIndexTasks[file]?.state = .preparing(
                preparationTaskID: preparationTaskID,
                indexTask: indexTask
              )
            }
          }
        }
      }

      let indexTask = Task(priority: priority) {
        await preparationTask?.waitToFinishPropagatingCancellation()

        // And after preparation is done, index the files in the targets.
        await withTaskGroup(of: Void.self) { taskGroup in
          let fileInfos = targetsBatch.flatMap { (target) -> [FileIndexInfo] in
            guard let files = filesByTarget[target] else {
              logger.fault("Unexpectedly found no files for target in target batch")
              return []
            }
            return files
          }
          let batches = await UpdateIndexStoreTaskDescription.batches(
            toIndex: fileInfos,
            buildServerManager: buildServerManager
          )
          for (target, language, fileBatch) in batches {
            taskGroup.addTask {
              let fileAndOutputPaths: [FileAndOutputPath] = fileBatch.compactMap {
                guard $0.target == target else {
                  logger.fault(
                    "FileIndexInfo refers to different target than should be indexed: \($0.target.forLogging) vs \(target.forLogging)"
                  )
                  return nil
                }
                return FileAndOutputPath(file: $0.file, outputPath: $0.outputPath)
              }
              await self.updateIndexStore(
                for: fileAndOutputPaths,
                target: target,
                language: language,
                indexFilesWithUpToDateUnit: indexFilesWithUpToDateUnit,
                preparationTaskID: preparationTaskID,
                priority: priority
              )
            }
          }
          await taskGroup.waitForAll()
        }
      }
      indexTasks.append(indexTask)

      for file in filesToIndex {
        // The state of `inProgressIndexTasks` will get pushed on from `updateIndexStore`.
        // The updates to `inProgressIndexTasks` from `updateIndexStore` cannot race with setting it to
        // `.waitingForPreparation` here  because we don't have an `await` call between the creation of `indexTask` and
        // this loop, so we still have exclusive access to the `SemanticIndexManager` actor and hence `updateIndexStore`
        // can't execute until we have set all index statuses to `.waitingForPreparation`.
        inProgressIndexTasks[file]?.state = .waitingForPreparation(
          preparationTaskID: preparationTaskID,
          indexTask: indexTask
        )
      }
    }

    return Task(priority: priority) {
      await indexTasks.concurrentForEach { await $0.value }
    }
  }
}
