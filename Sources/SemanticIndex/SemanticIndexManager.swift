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
import LSPLogging
import LanguageServerProtocol
import SKCore

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
  /// We are waiting for preparation of the file's target to finish before we can index it.
  ///
  /// `preparationTaskID` identifies the preparation task so that we can transition a file's index state to
  /// `updatingIndexStore` when its preparation task has finished.
  ///
  /// `indexTask` is a task that finishes after both preparation and index store update are done. Whoever owns the index
  /// task is still the sole owner of it and responsible for its cancellation.
  case waitingForPreparation(preparationTaskID: UUID, indexTask: Task<Void, Never>)

  /// The file's target has been prepared and we are updating the file's index store.
  ///
  /// `updateIndexStoreTask` is the task that updates the index store itself.
  ///
  /// `indexTask` is a task that finishes after both preparation and index store update are done. Whoever owns the index
  /// task is still the sole owner of it and responsible for its cancellation.
  case updatingIndexStore(updateIndexStoreTask: OpaqueQueuedIndexTask, indexTask: Task<Void, Never>)
}

/// Schedules index tasks and keeps track of the index status of files.
public final actor SemanticIndexManager {
  /// The underlying index. This is used to check if the index of a file is already up-to-date, in which case it doesn't
  /// need to be indexed again.
  private let index: UncheckedIndex

  /// The build system manager that is used to get compiler arguments for a file.
  private let buildSystemManager: BuildSystemManager

  private let testHooks: IndexTestHooks

  /// The task to generate the build graph (resolving package dependencies, generating the build description,
  /// ...). `nil` if no build graph is currently being generated.
  private var generateBuildGraphTask: Task<Void, Never>?

  private let preparationUpToDateStatus = IndexUpToDateStatusManager<ConfiguredTarget>()

  private let indexStoreUpToDateStatus = IndexUpToDateStatusManager<DocumentURI>()

  /// The preparation tasks that have been started and are either scheduled in the task scheduler or currently
  /// executing.
  ///
  /// After a preparation task finishes, it is removed from this dictionary.
  private var inProgressPreparationTasks: [ConfiguredTarget: OpaqueQueuedIndexTask] = [:]

  /// The files that are currently being index, either waiting for their target to be prepared, waiting for the index
  /// store update task to be scheduled in the task scheduler or which currently have an index store update running.
  ///
  /// After the file is indexed, it is removed from this dictionary.
  private var inProgressIndexTasks: [DocumentURI: InProgressIndexStore] = [:]

  /// The `TaskScheduler` that manages the scheduling of index tasks. This is shared among all `SemanticIndexManager`s
  /// in the process, to ensure that we don't schedule more index operations than processor cores from multiple
  /// workspaces.
  private let indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>

  /// Called when files are scheduled to be indexed.
  ///
  /// The parameter is the number of files that were scheduled to be indexed.
  private let indexTasksWereScheduled: @Sendable (_ numberOfFileScheduled: Int) -> Void

  /// Callback that is called when an index task has finished.
  ///
  /// An object observing this property probably wants to check `inProgressIndexTasks` when the callback is called to
  /// get the current list of in-progress index tasks.
  ///
  /// The number of `indexTaskDidFinish` calls does not have to relate to the number of `indexTasksWereScheduled` calls.
  private let indexTaskDidFinish: @Sendable () -> Void

  // MARK: - Public API

  /// The files that still need to be indexed.
  ///
  /// Scheduled tasks are files that are waiting for their target to be prepared or whose index store update task is
  /// waiting to be scheduled by the task scheduler.
  ///
  /// `executing` are the files that currently have an active index store update task running.
  public var inProgressIndexFiles: (scheduled: [DocumentURI], executing: [DocumentURI]) {
    var scheduled: [DocumentURI] = []
    var executing: [DocumentURI] = []
    for (uri, status) in inProgressIndexTasks {
      let isExecuting: Bool
      switch status {
      case .waitingForPreparation:
        isExecuting = false
      case .updatingIndexStore(updateIndexStoreTask: let updateIndexStoreTask, indexTask: _):
        isExecuting = updateIndexStoreTask.isExecuting
      }

      if isExecuting {
        executing.append(uri)
      } else {
        scheduled.append(uri)
      }
    }

    return (scheduled, executing)
  }

  public init(
    index: UncheckedIndex,
    buildSystemManager: BuildSystemManager,
    testHooks: IndexTestHooks,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>,
    indexTasksWereScheduled: @escaping @Sendable (Int) -> Void,
    indexTaskDidFinish: @escaping @Sendable () -> Void
  ) {
    self.index = index
    self.buildSystemManager = buildSystemManager
    self.testHooks = testHooks
    self.indexTaskScheduler = indexTaskScheduler
    self.indexTasksWereScheduled = indexTasksWereScheduled
    self.indexTaskDidFinish = indexTaskDidFinish
  }

  /// Schedules a task to index `files`. Files that are known to be up-to-date based on `indexStatus` will
  /// not be re-indexed. The method will re-index files even if they have a unit with a timestamp that matches the
  /// source file's mtime. This allows re-indexing eg. after compiler arguments or dependencies have changed.
  ///
  /// Returns immediately after scheduling that task.
  ///
  /// Indexing is being performed with a low priority.
  private func scheduleBackgroundIndex(files: some Collection<DocumentURI>) async {
    _ = await self.scheduleIndexing(of: files, priority: .low)
  }

  /// Regenerate the build graph (also resolving package dependencies) and then index all the source files known to the
  /// build system that don't currently have a unit with a timestamp that matches the mtime of the file.
  ///
  /// This method is intended to initially update the index of a project after it is opened.
  public func scheduleBuildGraphGenerationAndBackgroundIndexAllFiles() async {
    generateBuildGraphTask = Task(priority: .low) {
      await orLog("Generating build graph") { try await self.buildSystemManager.generateBuildGraph() }
      let index = index.checked(for: .modifiedFiles)
      let filesToIndex = await self.buildSystemManager.sourceFiles().lazy.map(\.uri)
        .filter { uri in
          guard let url = uri.fileURL else {
            // The URI is not a file, so there's nothing we can index.
            return false
          }
          return !index.hasUpToDateUnit(for: url)
        }
      await scheduleBackgroundIndex(files: filesToIndex)
      generateBuildGraphTask = nil
    }
  }

  /// Wait for all in-progress index tasks to finish.
  public func waitForUpToDateIndex() async {
    logger.info("Waiting for up-to-date index")
    // Wait for a build graph update first, if one is in progress. This will add all index tasks to `indexStatus`, so we
    // can await the index tasks below.
    await generateBuildGraphTask?.value

    await withTaskGroup(of: Void.self) { taskGroup in
      for (_, status) in inProgressIndexTasks {
        switch status {
        case .waitingForPreparation(preparationTaskID: _, indexTask: let indexTask),
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
  public func waitForUpToDateIndex(for uris: some Collection<DocumentURI>) async {
    logger.info(
      "Waiting for up-to-date index for \(uris.map { $0.fileURL?.lastPathComponent ?? $0.stringValue }.joined(separator: ", "))"
    )
    // If there's a build graph update in progress wait for that to finish so we can discover new files in the build
    // system.
    await generateBuildGraphTask?.value

    // Create a new index task for the files that aren't up-to-date. The newly scheduled index tasks will
    // - Wait for the existing index operations to finish if they have the same number of files.
    // - Reschedule the background index task in favor of an index task with fewer source files.
    await self.scheduleIndexing(of: uris, priority: nil).value
    index.pollForUnitChangesAndWait()
    logger.debug("Done waiting for up-to-date index")
  }

  public func filesDidChange(_ events: [FileEvent]) async {
    // We only re-index the files that were changed and don't re-index any of their dependencies. See the
    // `Documentation/Files_To_Reindex.md` file.
    let changedFiles = events.map(\.uri)
    await indexStoreUpToDateStatus.markOutOfDate(changedFiles)

    // Note that configured targets are the right abstraction layer here (instead of a non-configured target) because a
    // build system might have targets that include different source files. Hence a source file might be in target T
    // configured for macOS but not in target T configured for iOS.
    let targets = await changedFiles.asyncMap { await buildSystemManager.configuredTargets(for: $0) }.flatMap { $0 }
    if let dependentTargets = await buildSystemManager.targets(dependingOn: targets) {
      await preparationUpToDateStatus.markOutOfDate(dependentTargets)
    } else {
      // We couldn't determine which targets depend on the modified targets. Be conservative and assume all of them do.
      await indexStoreUpToDateStatus.markOutOfDate(changedFiles)

      await preparationUpToDateStatus.markAllOutOfDate()
      // `markAllOutOfDate` only marks targets out-of-date that have been indexed before. Also mark all targets with
      // in-progress preparation out of date. So we don't get into the following situation, which would result in an
      // incorrect up-to-date status of a target
      //  - Target preparation starts for the first time
      //  - Files changed
      //  - Target preparation finishes.
      await preparationUpToDateStatus.markOutOfDate(inProgressPreparationTasks.keys)
    }

    await scheduleBackgroundIndex(files: changedFiles)
  }

  /// Returns the files that should be indexed to get up-to-date index information for the given files.
  ///
  /// If `files` contains a header file, this will return a `FileToIndex` that re-indexes a main file which includes the
  /// header file to update the header file's index.
  private func filesToIndex(
    toCover files: some Collection<DocumentURI>
  ) async -> [FileToIndex] {
    let sourceFiles = Set(await buildSystemManager.sourceFiles().map(\.uri))
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
  public func schedulePreparation(of uri: DocumentURI, priority: TaskPriority? = nil) {
    Task(priority: priority) {
      await withLoggingScope("preparation") {
        guard let target = await buildSystemManager.canonicalConfiguredTarget(for: uri) else {
          return
        }
        await self.prepare(targets: [target], priority: priority)
      }
    }
  }

  // MARK: - Helper functions

  /// Prepare the given targets for indexing
  private func prepare(targets: [ConfiguredTarget], priority: TaskPriority?) async {
    // Perform a quick initial check whether the target is up-to-date, in which case we don't need to schedule a
    // preparation operation at all.
    // We will check the up-to-date status again in `PreparationTaskDescription.execute`. This ensures that if we
    // schedule two preparations of the same target in quick succession, only the first one actually performs a prepare
    // and the second one will be a no-op once it runs.
    let targetsToPrepare = await targets.asyncFilter {
      await !preparationUpToDateStatus.isUpToDate($0)
    }

    guard !targetsToPrepare.isEmpty else {
      return
    }

    let taskDescription = AnyIndexTaskDescription(
      PreparationTaskDescription(
        targetsToPrepare: targetsToPrepare,
        buildSystemManager: self.buildSystemManager,
        preparationUpToDateStatus: preparationUpToDateStatus,
        testHooks: testHooks
      )
    )
    let preparationTask = await indexTaskScheduler.schedule(priority: priority, taskDescription) { task, newState in
      guard case .finished = newState else {
        return
      }
      for target in targetsToPrepare {
        if self.inProgressPreparationTasks[target] == OpaqueQueuedIndexTask(task) {
          self.inProgressPreparationTasks[target] = nil
        }
      }
      self.indexTaskDidFinish()
    }
    for target in targetsToPrepare {
      inProgressPreparationTasks[target] = OpaqueQueuedIndexTask(preparationTask)
    }
    return await preparationTask.waitToFinishPropagatingCancellation()
  }

  /// Update the index store for the given files, assuming that their targets have already been prepared.
  private func updateIndexStore(
    for filesAndTargets: [FileAndTarget],
    preparationTaskID: UUID,
    priority: TaskPriority?
  ) async {
    let taskDescription = AnyIndexTaskDescription(
      UpdateIndexStoreTaskDescription(
        filesToIndex: filesAndTargets,
        buildSystemManager: self.buildSystemManager,
        index: index,
        indexStoreUpToDateStatus: indexStoreUpToDateStatus,
        testHooks: testHooks
      )
    )
    let updateIndexTask = await indexTaskScheduler.schedule(priority: priority, taskDescription) { task, newState in
      guard case .finished = newState else {
        return
      }
      for fileAndTarget in filesAndTargets {
        if case .updatingIndexStore(OpaqueQueuedIndexTask(task), _) = self.inProgressIndexTasks[
          fileAndTarget.file.sourceFile
        ] {
          self.inProgressIndexTasks[fileAndTarget.file.sourceFile] = nil
        }
      }
      self.indexTaskDidFinish()
    }
    for fileAndTarget in filesAndTargets {
      if case .waitingForPreparation(preparationTaskID, let indexTask) = inProgressIndexTasks[
        fileAndTarget.file.sourceFile
      ] {
        inProgressIndexTasks[fileAndTarget.file.sourceFile] = .updatingIndexStore(
          updateIndexStoreTask: OpaqueQueuedIndexTask(updateIndexTask),
          indexTask: indexTask
        )
      }
    }
    return await updateIndexTask.waitToFinishPropagatingCancellation()
  }

  /// Index the given set of files at the given priority, preparing their targets beforehand, if needed.
  ///
  /// The returned task finishes when all files are indexed.
  private func scheduleIndexing(
    of files: some Collection<DocumentURI>,
    priority: TaskPriority?
  ) async -> Task<Void, Never> {
    // Perform a quick initial check to whether the files is up-to-date, in which case we don't need to schedule a
    // prepare and index operation at all.
    // We will check the up-to-date status again in `IndexTaskDescription.execute`. This ensures that if we schedule
    // schedule two indexing jobs for the same file in quick succession, only the first one actually updates the index
    // store and the second one will be a no-op once it runs.
    let outOfDateFiles = await filesToIndex(toCover: files).asyncFilter {
      return await !indexStoreUpToDateStatus.isUpToDate($0.sourceFile)
    }
    // sort files to get deterministic indexing order
    .sorted(by: { $0.sourceFile.stringValue < $1.sourceFile.stringValue })

    // Sort the targets in topological order so that low-level targets get built before high-level targets, allowing us
    // to index the low-level targets ASAP.
    var filesByTarget: [ConfiguredTarget: [FileToIndex]] = [:]
    for fileToIndex in outOfDateFiles {
      guard let target = await buildSystemManager.canonicalConfiguredTarget(for: fileToIndex.mainFile) else {
        logger.error(
          "Not indexing \(fileToIndex.forLogging) because the target could not be determined"
        )
        continue
      }
      filesByTarget[target, default: []].append(fileToIndex)
    }

    var sortedTargets: [ConfiguredTarget] =
      await orLog("Sorting targets") { try await buildSystemManager.topologicalSort(of: Array(filesByTarget.keys)) }
      ?? Array(filesByTarget.keys).sorted(by: {
        ($0.targetID, $0.runDestinationID) < ($1.targetID, $1.runDestinationID)
      })

    if Set(sortedTargets) != Set(filesByTarget.keys) {
      logger.fault(
        """
        Sorting targets topologically changed set of targets:
        \(sortedTargets.map(\.targetID).joined(separator: ", ")) != \(filesByTarget.keys.map(\.targetID).joined(separator: ", "))
        """
      )
      sortedTargets = Array(filesByTarget.keys).sorted(by: {
        ($0.targetID, $0.runDestinationID) < ($1.targetID, $1.runDestinationID)
      })
    }

    var indexTasks: [Task<Void, Never>] = []

    // TODO (indexing): When we can index multiple targets concurrently in SwiftPM, increase the batch size to half the
    // processor count, so we can get parallelism during preparation.
    // https://github.com/apple/sourcekit-lsp/issues/1262
    for targetsBatch in sortedTargets.partition(intoBatchesOfSize: 1) {
      let preparationTaskID = UUID()
      let indexTask = Task(priority: priority) {
        // First prepare the targets.
        await prepare(targets: targetsBatch, priority: priority)

        // And after preparation is done, index the files in the targets.
        await withTaskGroup(of: Void.self) { taskGroup in
          for target in targetsBatch {
            // TODO (indexing): Once swiftc supports indexing of multiple files in a single invocation, increase the
            // batch size to allow it to share AST builds between multiple files within a target.
            // https://github.com/apple/sourcekit-lsp/issues/1268
            for fileBatch in filesByTarget[target]!.partition(intoBatchesOfSize: 1) {
              taskGroup.addTask {
                await self.updateIndexStore(
                  for: fileBatch.map { FileAndTarget(file: $0, target: target) },
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

      let filesToIndex = targetsBatch.flatMap({ filesByTarget[$0]! })
      for file in filesToIndex {
        // indexStatus will get set to `.upToDate` by `updateIndexStore`. Setting it to `.upToDate` cannot race with
        // setting it to `.scheduled` because we don't have an `await` call between the creation of `indexTask` and
        // this loop, so we still have exclusive access to the `SemanticIndexManager` actor and hence `updateIndexStore`
        // can't execute until we have set all index statuses to `.scheduled`.
        inProgressIndexTasks[file.sourceFile] = .waitingForPreparation(
          preparationTaskID: preparationTaskID,
          indexTask: indexTask
        )
      }
      indexTasksWereScheduled(filesToIndex.count)
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
