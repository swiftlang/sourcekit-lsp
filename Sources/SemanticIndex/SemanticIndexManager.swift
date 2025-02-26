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

import LanguageServerProtocolExtensions

#if compiler(>=6)
package import BuildServerProtocol
package import BuildSystemIntegration
import Foundation
package import LanguageServerProtocol
import SKLogging
import SwiftExtensions
#else
import BuildServerProtocol
import BuildSystemIntegration
import Foundation
import LanguageServerProtocol
import SKLogging
import SwiftExtensions
#endif

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

private enum InProgressIndexStore {
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
package enum IndexProgressStatus: Sendable {
  case preparingFileForEditorFunctionality
  case schedulingIndexing
  case indexing(preparationTasks: [BuildTargetIdentifier: IndexTaskStatus], indexTasks: [DocumentURI: IndexTaskStatus])
  case upToDate

  package func merging(with other: IndexProgressStatus) -> IndexProgressStatus {
    switch (self, other) {
    case (_, .preparingFileForEditorFunctionality), (.preparingFileForEditorFunctionality, _):
      return .preparingFileForEditorFunctionality
    case (_, .schedulingIndexing), (.schedulingIndexing, _):
      return .schedulingIndexing
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
fileprivate struct InProgressPrepareForEditorTask {
  /// A unique ID that identifies the preparation task and is used to set
  /// `SemanticIndexManager.inProgressPrepareForEditorTask` to `nil`  when the current in progress task finishes.
  let id: UUID

  /// The document that is being prepared.
  let document: DocumentURI

  /// The task that prepares the document. Should never be awaited and only be used to cancel the task.
  let task: Task<Void, Never>
}

/// The reason why a target is being prepared. This is used to determine the `IndexProgressStatus`.
fileprivate enum TargetPreparationPurpose: Comparable {
  /// We are preparing the target so we can index files in it.
  case forIndexing

  /// We are preparing the target to provide semantic functionality in one of its files.
  case forEditorFunctionality
}

/// An entry in `SemanticIndexManager.inProgressPreparationTasks`.
fileprivate struct InProgressPreparationTask {
  let task: OpaqueQueuedIndexTask
  let purpose: TargetPreparationPurpose
}

/// Schedules index tasks and keeps track of the index status of files.
package final actor SemanticIndexManager {
  /// The underlying index. This is used to check if the index of a file is already up-to-date, in which case it doesn't
  /// need to be indexed again.
  private let index: UncheckedIndex

  /// The build system manager that is used to get compiler arguments for a file.
  private let buildSystemManager: BuildSystemManager

  /// How long to wait until we cancel an update indexstore task. This timeout should be long enough that all
  /// `swift-frontend` tasks finish within it. It prevents us from blocking the index if the type checker gets stuck on
  /// an expression for a long time.
  package var updateIndexStoreTimeout: Duration

  private let hooks: IndexHooks

  /// The tasks to generate the build graph (resolving package dependencies, generating the build description,
  /// ...) and to schedule indexing of modified tasks.
  private var scheduleIndexingTasks: [UUID: Task<Void, Never>] = [:]

  private let preparationUpToDateTracker = UpToDateTracker<BuildTargetIdentifier>()

  private let indexStoreUpToDateTracker = UpToDateTracker<DocumentURI>()

  /// The preparation tasks that have been started and are either scheduled in the task scheduler or currently
  /// executing.
  ///
  /// After a preparation task finishes, it is removed from this dictionary.
  private var inProgressPreparationTasks: [BuildTargetIdentifier: InProgressPreparationTask] = [:]

  /// The files that are currently being index, either waiting for their target to be prepared, waiting for the index
  /// store update task to be scheduled in the task scheduler or which currently have an index store update running.
  ///
  /// After the file is indexed, it is removed from this dictionary.
  private var inProgressIndexTasks: [DocumentURI: InProgressIndexStore] = [:]

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
  private let logMessageToIndexLog: @Sendable (_ taskID: String, _ message: String) -> Void

  /// Called when files are scheduled to be indexed.
  ///
  /// The parameter is the number of files that were scheduled to be indexed.
  private let indexTasksWereScheduled: @Sendable (_ numberOfFileScheduled: Int) -> Void

  /// Callback that is called when `progressStatus` might have changed.
  private let indexProgressStatusDidChange: @Sendable () -> Void

  // MARK: - Public API

  /// A summary of the tasks that this `SemanticIndexManager` has currently scheduled or is currently indexing.
  package var progressStatus: IndexProgressStatus {
    if inProgressPreparationTasks.values.contains(where: { $0.purpose == .forEditorFunctionality }) {
      return .preparingFileForEditorFunctionality
    }
    if !scheduleIndexingTasks.isEmpty {
      return .schedulingIndexing
    }
    let preparationTasks = inProgressPreparationTasks.mapValues { inProgressTask in
      return inProgressTask.task.isExecuting ? IndexTaskStatus.executing : IndexTaskStatus.scheduled
    }
    let indexTasks = inProgressIndexTasks.mapValues { status in
      switch status {
      case .waitingForPreparation, .preparing:
        return IndexTaskStatus.scheduled
      case .updatingIndexStore(updateIndexStoreTask: let updateIndexStoreTask, indexTask: _):
        return updateIndexStoreTask.isExecuting ? IndexTaskStatus.executing : IndexTaskStatus.scheduled
      }
    }
    if preparationTasks.isEmpty && indexTasks.isEmpty {
      return .upToDate
    }
    return .indexing(preparationTasks: preparationTasks, indexTasks: indexTasks)
  }

  package init(
    index: UncheckedIndex,
    buildSystemManager: BuildSystemManager,
    updateIndexStoreTimeout: Duration,
    hooks: IndexHooks,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>,
    logMessageToIndexLog: @escaping @Sendable (_ taskID: String, _ message: String) -> Void,
    indexTasksWereScheduled: @escaping @Sendable (Int) -> Void,
    indexProgressStatusDidChange: @escaping @Sendable () -> Void
  ) {
    self.index = index
    self.buildSystemManager = buildSystemManager
    self.updateIndexStoreTimeout = updateIndexStoreTimeout
    self.hooks = hooks
    self.indexTaskScheduler = indexTaskScheduler
    self.logMessageToIndexLog = logMessageToIndexLog
    self.indexTasksWereScheduled = indexTasksWereScheduled
    self.indexProgressStatusDidChange = indexProgressStatusDidChange
  }

  /// Schedules a task to index `files`. Files that are known to be up-to-date based on `indexStatus` will
  /// not be re-indexed. The method will re-index files even if they have a unit with a timestamp that matches the
  /// source file's mtime. This allows re-indexing eg. after compiler arguments or dependencies have changed.
  ///
  /// Returns immediately after scheduling that task.
  ///
  /// Indexing is being performed with a low priority.
  private func scheduleBackgroundIndex(
    files: some Collection<DocumentURI> & Sendable,
    indexFilesWithUpToDateUnit: Bool
  ) async {
    _ = await self.scheduleIndexing(of: files, indexFilesWithUpToDateUnit: indexFilesWithUpToDateUnit, priority: .low)
  }

  /// Regenerate the build graph (also resolving package dependencies) and then index all the source files known to the
  /// build system that don't currently have a unit with a timestamp that matches the mtime of the file.
  ///
  /// If `filesToIndex` is `nil`, all files in the build system with out-of-date units are indexed.
  ///
  /// If `ensureAllUnitsRegisteredInIndex` is `true`, ensure that all units are registered in the index before
  /// triggering the indexing. This is a costly operation since it iterates through all the unit files on the file
  /// system but if existing unit files are not known to the index, we might re-index those files even if they are
  /// up-to-date. Generally this should be set to `true` during the initial indexing (in which case we might be need to
  /// build the indexstore-db) and `false` for all subsequent indexing.
  package func scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(
    filesToIndex: [DocumentURI]?,
    ensureAllUnitsRegisteredInIndex: Bool,
    indexFilesWithUpToDateUnit: Bool
  ) async {
    let taskId = UUID()
    let generateBuildGraphTask = Task(priority: .low) {
      await withLoggingSubsystemAndScope(subsystem: indexLoggingSubsystem, scope: "build-graph-generation") {
        await hooks.buildGraphGenerationDidStart?()
        await self.buildSystemManager.waitForUpToDateBuildGraph()
        if ensureAllUnitsRegisteredInIndex {
          index.pollForUnitChangesAndWait()
        }
        await hooks.buildGraphGenerationDidFinish?()
        // TODO: Ideally this would be a type like any Collection<DocumentURI> & Sendable but that doesn't work due to
        // https://github.com/swiftlang/swift/issues/75602
        var filesToIndex: [DocumentURI] =
          if let filesToIndex {
            filesToIndex
          } else {
            await orLog("Getting files to index") {
              try await self.buildSystemManager.sourceFiles(includeNonBuildableFiles: false).keys
                .sorted { $0.stringValue < $1.stringValue }
            } ?? []
          }
        if !indexFilesWithUpToDateUnit {
          let index = index.checked(for: .modifiedFiles)
          filesToIndex = filesToIndex.filter {
            if index.hasUpToDateUnit(for: $0) {
              return false
            }
            if case .waitingForPreparation = inProgressIndexTasks[$0] {
              // We haven't started preparing the file yet. Scheduling a new index operation for it won't produce any
              // more recent results.
              return false
            }
            return true
          }
        }
        await scheduleBackgroundIndex(files: filesToIndex, indexFilesWithUpToDateUnit: indexFilesWithUpToDateUnit)
        scheduleIndexingTasks[taskId] = nil
      }
    }
    scheduleIndexingTasks[taskId] = generateBuildGraphTask
    indexProgressStatusDidChange()
  }

  /// Causes all files to be re-indexed even if the unit file for the source file is up to date.
  /// See `TriggerReindexRequest`.
  package func scheduleReindex() async {
    await indexStoreUpToDateTracker.markAllKnownOutOfDate()
    await preparationUpToDateTracker.markAllKnownOutOfDate()
    await scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(
      filesToIndex: nil,
      ensureAllUnitsRegisteredInIndex: false,
      indexFilesWithUpToDateUnit: true
    )
  }

  private func waitForBuildGraphGenerationTasks() async {
    await withTaskGroup(of: Void.self) { taskGroup in
      for generateBuildGraphTask in scheduleIndexingTasks.values {
        taskGroup.addTask {
          await generateBuildGraphTask.value
        }
      }
    }
  }

  /// Wait for all in-progress index tasks to finish.
  package func waitForUpToDateIndex() async {
    logger.info("Waiting for up-to-date index")
    // Wait for a build graph update first, if one is in progress. This will add all index tasks to `indexStatus`, so we
    // can await the index tasks below.
    await waitForBuildGraphGenerationTasks()

    await withTaskGroup(of: Void.self) { taskGroup in
      for (_, status) in inProgressIndexTasks {
        switch status {
        case .waitingForPreparation(preparationTaskID: _, indexTask: let indexTask),
          .preparing(preparationTaskID: _, indexTask: let indexTask),
          .updatingIndexStore(updateIndexStoreTask: _, indexTask: let indexTask):
          taskGroup.addTask {
            await indexTask.value
          }
        }
      }
      await taskGroup.waitForAll()
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
    // If there's a build graph update in progress wait for that to finish so we can discover new files in the build
    // system.
    await waitForBuildGraphGenerationTasks()

    // Create a new index task for the files that aren't up-to-date. The newly scheduled index tasks will
    // - Wait for the existing index operations to finish if they have the same number of files.
    // - Reschedule the background index task in favor of an index task with fewer source files.
    await self.scheduleIndexing(of: uris, indexFilesWithUpToDateUnit: false, priority: nil).value
    index.pollForUnitChangesAndWait()
    logger.debug("Done waiting for up-to-date index")
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    // We only re-index the files that were changed and don't re-index any of their dependencies. See the
    // `Documentation/Files_To_Reindex.md` file.
    let changedFiles = events.map(\.uri)
    await indexStoreUpToDateTracker.markOutOfDate(changedFiles)

    // Preparation tracking should be per file. For now consider any non-known-language change as having to re-prepare
    // the target itself so that we re-prepare potential input files to plugins.
    // https://github.com/swiftlang/sourcekit-lsp/issues/1975
    var outOfDateTargets = Set<BuildTargetIdentifier>()
    for file in changedFiles {
      let changedTargets = await buildSystemManager.targets(for: file)
      if Language(inferredFromFileExtension: file) == nil {
        outOfDateTargets.formUnion(changedTargets)
      }

      let dependentTargets = await buildSystemManager.targets(dependingOn: changedTargets)
      outOfDateTargets.formUnion(dependentTargets)
    }
    if !outOfDateTargets.isEmpty {
      logger.info(
        """
        Marking dependent targets as out-of-date: \
        \(String(outOfDateTargets.map(\.uri.stringValue).joined(separator: ", ")))
        """
      )
      await preparationUpToDateTracker.markOutOfDate(outOfDateTargets)
    }

    await scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(
      filesToIndex: changedFiles,
      ensureAllUnitsRegisteredInIndex: false,
      indexFilesWithUpToDateUnit: false
    )
  }

  /// Returns the files that should be indexed to get up-to-date index information for the given files.
  ///
  /// If `files` contains a header file, this will return a `FileToIndex` that re-indexes a main file which includes the
  /// header file to update the header file's index.
  private func filesToIndex(
    toCover files: some Collection<DocumentURI> & Sendable
  ) async -> [FileToIndex] {
    let sourceFiles = await orLog("Getting source files in project") {
      Set(try await buildSystemManager.sourceFiles(includeNonBuildableFiles: false).keys)
    }
    guard let sourceFiles else {
      return []
    }
    let filesToReIndex = await files.asyncCompactMap { (uri) -> FileToIndex? in
      if sourceFiles.contains(uri) {
        // If this is a source file, just index it.
        return .indexableFile(uri)
      }
      // Otherwise, see if it is a header file. If so, index a main file that that imports it to update header file's
      // index.
      // Deterministically pick a main file. This ensures that we always pick the same main file for a header. This way,
      // if we request the same header to be indexed twice, we'll pick the same unit file the second time around,
      // realize that its timestamp is later than the modification date of the header and we don't need to re-index.
      let mainFile = index.checked(for: .deletedFiles)
        .mainFilesContainingFile(uri: uri, crossLanguage: false)
        .sorted(by: { $0.stringValue < $1.stringValue }).first
      guard let mainFile else {
        return nil
      }
      return .headerFile(header: uri, mainFile: mainFile)
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
    guard let target = await buildSystemManager.canonicalTarget(for: uri) else {
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

  private func prepare(
    targets: [BuildTargetIdentifier],
    purpose: TargetPreparationPurpose,
    priority: TaskPriority?,
    executionStatusChangedCallback: @escaping (QueuedTask<AnyIndexTaskDescription>, TaskExecutionState) async -> Void =
      { _, _ in }
  ) async {
    // Perform a quick initial check whether the target is up-to-date, in which case we don't need to schedule a
    // preparation operation at all.
    // We will check the up-to-date status again in `PreparationTaskDescription.execute`. This ensures that if we
    // schedule two preparations of the same target in quick succession, only the first one actually performs a prepare
    // and the second one will be a no-op once it runs.
    let targetsToPrepare = await targets.asyncFilter {
      await !preparationUpToDateTracker.isUpToDate($0)
    }

    guard !targetsToPrepare.isEmpty else {
      return
    }

    let taskDescription = AnyIndexTaskDescription(
      PreparationTaskDescription(
        targetsToPrepare: targetsToPrepare,
        buildSystemManager: self.buildSystemManager,
        preparationUpToDateTracker: preparationUpToDateTracker,
        logMessageToIndexLog: logMessageToIndexLog,
        hooks: hooks
      )
    )
    if Task.isCancelled {
      return
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

  /// Update the index store for the given files, assuming that their targets have already been prepared.
  private func updateIndexStore(
    for filesAndTargets: [FileAndTarget],
    indexFilesWithUpToDateUnit: Bool,
    preparationTaskID: UUID,
    priority: TaskPriority?
  ) async {
    let taskDescription = AnyIndexTaskDescription(
      UpdateIndexStoreTaskDescription(
        filesToIndex: filesAndTargets,
        buildSystemManager: self.buildSystemManager,
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
      for fileAndTarget in filesAndTargets {
        switch self.inProgressIndexTasks[fileAndTarget.file.sourceFile] {
        case .updatingIndexStore(let registeredTask, _):
          if registeredTask == OpaqueQueuedIndexTask(task) {
            self.inProgressIndexTasks[fileAndTarget.file.sourceFile] = nil
          }
        case .waitingForPreparation(let registeredTask, _), .preparing(let registeredTask, _):
          if registeredTask == preparationTaskID {
            self.inProgressIndexTasks[fileAndTarget.file.sourceFile] = nil
          }
        case nil:
          break
        }
      }
      self.indexProgressStatusDidChange()
    }
    for fileAndTarget in filesAndTargets {
      switch inProgressIndexTasks[fileAndTarget.file.sourceFile] {
      case .waitingForPreparation(preparationTaskID, let indexTask), .preparing(preparationTaskID, let indexTask):
        inProgressIndexTasks[fileAndTarget.file.sourceFile] = .updatingIndexStore(
          updateIndexStoreTask: OpaqueQueuedIndexTask(updateIndexTask),
          indexTask: indexTask
        )
      default: break
      }
    }
    return await updateIndexTask.waitToFinishPropagatingCancellation()
  }

  /// Index the given set of files at the given priority, preparing their targets beforehand, if needed.
  ///
  /// The returned task finishes when all files are indexed.
  private func scheduleIndexing(
    of files: some Collection<DocumentURI> & Sendable,
    indexFilesWithUpToDateUnit: Bool,
    priority: TaskPriority?
  ) async -> Task<Void, Never> {
    // Perform a quick initial check to whether the files is up-to-date, in which case we don't need to schedule a
    // prepare and index operation at all.
    // We will check the up-to-date status again in `IndexTaskDescription.execute`. This ensures that if we schedule
    // schedule two indexing jobs for the same file in quick succession, only the first one actually updates the index
    // store and the second one will be a no-op once it runs.
    let outOfDateFiles = await filesToIndex(toCover: files).asyncFilter {
      if await indexStoreUpToDateTracker.isUpToDate($0.sourceFile) {
        return false
      }
      return true
    }
    // sort files to get deterministic indexing order
    .sorted(by: { $0.sourceFile.stringValue < $1.sourceFile.stringValue })
    logger.debug("Scheduling indexing of \(outOfDateFiles.map(\.sourceFile.stringValue).joined(separator: ", "))")

    // Sort the targets in topological order so that low-level targets get built before high-level targets, allowing us
    // to index the low-level targets ASAP.
    var filesByTarget: [BuildTargetIdentifier: [FileToIndex]] = [:]
    for fileToIndex in outOfDateFiles {
      guard let target = await buildSystemManager.canonicalTarget(for: fileToIndex.mainFile) else {
        logger.error(
          "Not indexing \(fileToIndex.forLogging) because the target could not be determined"
        )
        continue
      }
      guard let language = await buildSystemManager.defaultLanguage(for: fileToIndex.mainFile, in: target),
        UpdateIndexStoreTaskDescription.canIndex(language: language)
      else {
        continue
      }

      filesByTarget[target, default: []].append(fileToIndex)
    }

    // The targets sorted in reverse topological order, low-level targets before high-level targets. If topological
    // sorting fails, sorted in another deterministic way where the actual order doesn't matter.
    var sortedTargets: [BuildTargetIdentifier] =
      await orLog("Sorting targets") { try await buildSystemManager.topologicalSort(of: Array(filesByTarget.keys)) }
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
    for targetsBatch in sortedTargets.partition(intoBatchesOfSize: 1) {
      let preparationTaskID = UUID()
      let filesToIndex = targetsBatch.flatMap({ filesByTarget[$0]! })

      let indexTask = Task(priority: priority) {
        // First prepare the targets.
        await prepare(targets: targetsBatch, purpose: .forIndexing, priority: priority) { task, newState in
          if case .executing = newState {
            for file in filesToIndex {
              if case .waitingForPreparation(preparationTaskID: preparationTaskID, indexTask: let indexTask) =
                self.inProgressIndexTasks[file.sourceFile]
              {
                self.inProgressIndexTasks[file.sourceFile] = .preparing(
                  preparationTaskID: preparationTaskID,
                  indexTask: indexTask
                )
              }
            }
          }
        }

        // And after preparation is done, index the files in the targets.
        await withTaskGroup(of: Void.self) { taskGroup in
          for target in targetsBatch {
            // TODO: Once swiftc supports indexing of multiple files in a single invocation, increase the batch size to
            // allow it to share AST builds between multiple files within a target.
            // (https://github.com/swiftlang/sourcekit-lsp/issues/1268)
            for fileBatch in filesByTarget[target]!.partition(intoBatchesOfSize: 1) {
              taskGroup.addTask {
                await self.updateIndexStore(
                  for: fileBatch.map { FileAndTarget(file: $0, target: target) },
                  indexFilesWithUpToDateUnit: indexFilesWithUpToDateUnit,
                  preparationTaskID: preparationTaskID,
                  priority: priority
                )
              }
            }
          }
          await taskGroup.waitForAll()
        }
      }
      indexTasks.append(indexTask)

      // The number of index tasks that don't currently have an in-progress task associated with it.
      // The denominator in the index progress should get incremented by this amount.
      // We don't want to increment the denominator for tasks that already have an index in progress.
      let newIndexTasks = filesToIndex.filter { inProgressIndexTasks[$0.sourceFile] == nil }.count
      for file in filesToIndex {
        // The state of `inProgressIndexTasks` will get pushed on from `updateIndexStore`.
        // The updates to `inProgressIndexTasks` from `updateIndexStore` cannot race with setting it to
        // `.waitingForPreparation` here  because we don't have an `await` call between the creation of `indexTask` and
        // this loop, so we still have exclusive access to the `SemanticIndexManager` actor and hence `updateIndexStore`
        // can't execute until we have set all index statuses to `.waitingForPreparation`.
        inProgressIndexTasks[file.sourceFile] = .waitingForPreparation(
          preparationTaskID: preparationTaskID,
          indexTask: indexTask
        )
      }
      indexTasksWereScheduled(newIndexTasks)
    }
    let indexTasksImmutable = indexTasks

    return Task(priority: priority) {
      await withTaskGroup(of: Void.self) { taskGroup in
        for indexTask in indexTasksImmutable {
          taskGroup.addTask {
            await indexTask.value
          }
        }
        await taskGroup.waitForAll()
      }
    }
  }
}
