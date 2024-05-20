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

/// Describes the state of indexing for a single source file
private enum IndexStatus<T> {
  /// The index is up-to-date.
  case upToDate
  /// The file or target is not up to date. We have scheduled a task to update the index store for the file / prepare
  /// the target, but that index operation hasn't been started yet.
  case scheduled(T)
  /// We are currently actively updating the index store for the file / preparing the target, ie. we are running a
  /// subprocess that updates the index store / prepares a target.
  case executing(T)

  var description: String {
    switch self {
    case .upToDate:
      return "upToDate"
    case .scheduled:
      return "scheduled"
    case .executing:
      return "executing"
    }
  }
}

/// Schedules index tasks and keeps track of the index status of files.
public final actor SemanticIndexManager {
  /// The underlying index. This is used to check if the index of a file is already up-to-date, in which case it doesn't
  /// need to be indexed again.
  private let index: UncheckedIndex

  /// The build system manager that is used to get compiler arguments for a file.
  private let buildSystemManager: BuildSystemManager

  /// The task to generate the build graph (resolving package dependencies, generating the build description,
  /// ...). `nil` if no build graph is currently being generated.
  private var generateBuildGraphTask: Task<Void, Never>?

  /// The preparation status of the targets that the `SemanticIndexManager` has started preparation for.
  ///
  /// Targets will be removed from this dictionary when they are no longer known to be up-to-date.
  ///
  /// The associated values of the `IndexStatus` are:
  ///  - A UUID to track the task. This is used to ensure that status updates from this task don't update
  ///    `preparationStatus` for targets that are tracked by a different task.
  ///  - The list of targets that are being prepared in a joint preparation operation
  ///  - The task that prepares the target
  private var preparationStatus: [ConfiguredTarget: IndexStatus<(UUID, [ConfiguredTarget], Task<Void, Never>)>] = [:]

  /// The index status of the source files that the `SemanticIndexManager` knows about.
  ///
  /// Files will be removed from this dictionary if their index is no longer up-to-date.
  ///
  /// The associated values of the `IndexStatus` are:
  ///  - A UUID to track the task. This is used to ensure that status updates from this task don't update
  ///    `preparationStatus` for targets that are tracked by a different task.
  ///  - The task that prepares the target
  private var indexStatus: [DocumentURI: IndexStatus<(UUID, Task<Void, Never>)>] = [:]

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
  /// See `FileIndexStatus` for the distinction between `scheduled` and `executing`.
  public var inProgressIndexTasks: (scheduled: [DocumentURI], executing: [DocumentURI]) {
    let scheduled = indexStatus.compactMap { (uri: DocumentURI, status: IndexStatus) in
      if case .scheduled = status {
        return uri
      }
      return nil
    }
    let inProgress = indexStatus.compactMap { (uri: DocumentURI, status: IndexStatus) in
      if case .executing = status {
        return uri
      }
      return nil
    }
    return (scheduled, inProgress)
  }

  public init(
    index: UncheckedIndex,
    buildSystemManager: BuildSystemManager,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>,
    indexTasksWereScheduled: @escaping @Sendable (Int) -> Void,
    indexTaskDidFinish: @escaping @Sendable () -> Void
  ) {
    self.index = index
    self.buildSystemManager = buildSystemManager
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
      for (_, status) in indexStatus {
        switch status {
        case .scheduled((_, let task)), .executing((_, let task)):
          taskGroup.addTask {
            await task.value
          }
        case .upToDate:
          break
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
    // Reset the index status for these files so they get re-indexed by `index(files:priority:)`
    for uri in changedFiles {
      indexStatus[uri] = nil
    }
    // Note that configured targets are the right abstraction layer here (instead of a non-configured target) because a
    // build system might have targets that include different source files. Hence a source file might be in target T
    // configured for macOS but not in target T configured for iOS.
    let targets = await changedFiles.asyncMap { await buildSystemManager.configuredTargets(for: $0) }.flatMap { $0 }
    if let dependentTargets = await buildSystemManager.targets(dependingOn: targets) {
      for dependentTarget in dependentTargets {
        preparationStatus[dependentTarget] = nil
      }
    } else {
      // We couldn't determine which targets depend on the modified targets. Be conservative and assume all of them do.
      preparationStatus = [:]
    }

    await scheduleBackgroundIndex(files: changedFiles)
  }

  /// Returns the files that should be indexed to get up-to-date index information for the given files.
  ///
  /// If `files` contains a header file, this will return a `FileToIndex` that re-indexes a main file which includes the
  /// header file to update the header file's index.
  private func filesToIndex(toCover files: some Collection<DocumentURI>) async -> [FileToIndex] {
    let sourceFiles = Set(await buildSystemManager.sourceFiles().map(\.uri))
    let filesToReIndex = await files.asyncCompactMap { (uri) -> FileToIndex? in
      if sourceFiles.contains(uri) {
        // If this is a source file, just index it.
        return FileToIndex(uri: uri, mainFile: nil)
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
      return FileToIndex(uri: uri, mainFile: mainFile)
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
    var targetsToPrepare: [ConfiguredTarget] = []
    var preparationTasksToAwait: [Task<Void, Never>] = []
    for target in targets {
      switch preparationStatus[target] {
      case .upToDate:
        break
      case .scheduled((_, let existingTaskTargets, let task)), .executing((_, let existingTaskTargets, let task)):
        // If we already have a task scheduled that prepares fewer targets, await that instead of overriding the
        // target's preparation status with a longer-running task. The key benefit here is that when we get many
        // preparation requests for the same target (eg. one for every text document request sent to a file), we don't
        // re-create new `PreparationTaskDescription`s for every preparation request. Instead, all the preparation
        // requests await the same task. At the same time, if we have a multi-file preparation request and then get a
        // single-file preparation request, we will override the preparation of that target with the single-file
        // preparation task, ensuring that the task gets prepared as quickly as possible.
        if existingTaskTargets.count <= targets.count {
          preparationTasksToAwait.append(task)
        } else {
          targetsToPrepare.append(target)
        }
      case nil:
        targetsToPrepare.append(target)
      }
    }

    let taskDescription = AnyIndexTaskDescription(
      PreparationTaskDescription(
        targetsToPrepare: targetsToPrepare,
        buildSystemManager: self.buildSystemManager
      )
    )
    if !targetsToPrepare.isEmpty {
      // A UUID that is used to identify the task. This ensures that status updates from this task don't update
      // `preparationStatus` for targets that are tracked by a different task, eg. because this task is a multi-target
      // preparation task and the target's status is now tracked by a single-file preparation task.
      let taskID = UUID()
      let preparationTask = await self.indexTaskScheduler.schedule(priority: priority, taskDescription) { newState in
        switch newState {
        case .executing:
          for target in targetsToPrepare {
            if case .scheduled((taskID, let targets, let task)) = self.preparationStatus[target] {
              self.preparationStatus[target] = .executing((taskID, targets, task))
            }
          }
        case .cancelledToBeRescheduled:
          for target in targetsToPrepare {
            if case .executing((taskID, let targets, let task)) = self.preparationStatus[target] {
              self.preparationStatus[target] = .scheduled((taskID, targets, task))
            }
          }
        case .finished:
          for target in targetsToPrepare {
            switch self.preparationStatus[target] {
            case .executing((taskID, _, _)):
              self.preparationStatus[target] = .upToDate
            default:
              break
            }
          }
          self.indexTaskDidFinish()
        }
      }
      for target in targetsToPrepare {
        preparationStatus[target] = .scheduled((taskID, targetsToPrepare, preparationTask))
      }
      preparationTasksToAwait.append(preparationTask)
    }
    await withTaskGroup(of: Void.self) { taskGroup in
      for task in preparationTasksToAwait {
        taskGroup.addTask {
          await task.value
        }
      }
      await taskGroup.waitForAll()
    }
  }

  /// Update the index store for the given files, assuming that their targets have already been prepared.
  private func updateIndexStore(for files: [FileToIndex], taskID: UUID, priority: TaskPriority?) async {
    let taskDescription = AnyIndexTaskDescription(
      UpdateIndexStoreTaskDescription(
        filesToIndex: Set(files),
        buildSystemManager: self.buildSystemManager,
        index: index
      )
    )
    let updateIndexStoreTask = await self.indexTaskScheduler.schedule(priority: priority, taskDescription) { newState in
      switch newState {
      case .executing:
        for file in files {
          if case .scheduled((taskID, let task)) = self.indexStatus[file.uri] {
            self.indexStatus[file.uri] = .executing((taskID, task))
          }
        }
      case .cancelledToBeRescheduled:
        for file in files {
          if case .executing((taskID, let task)) = self.indexStatus[file.uri] {
            self.indexStatus[file.uri] = .scheduled((taskID, task))
          }
        }
      case .finished:
        for file in files {
          switch self.indexStatus[file.uri] {
          case .executing((taskID, _)):
            self.indexStatus[file.uri] = .upToDate
          default:
            break
          }
        }
        self.indexTaskDidFinish()
      }
    }
    await updateIndexStoreTask.value
  }

  /// Index the given set of files at the given priority, preparing their targets beforehand, if needed.
  ///
  /// The returned task finishes when all files are indexed.
  private func scheduleIndexing(
    of files: some Collection<DocumentURI>,
    priority: TaskPriority?
  ) async -> Task<Void, Never> {
    let outOfDateFiles = await filesToIndex(toCover: files).filter {
      if case .upToDate = indexStatus[$0.uri] {
        return false
      }
      return true
    }
    .sorted(by: { $0.uri.stringValue < $1.uri.stringValue })  // sort files to get deterministic indexing order

    // Sort the targets in topological order so that low-level targets get built before high-level targets, allowing us
    // to index the low-level targets ASAP.
    var filesByTarget: [ConfiguredTarget: [FileToIndex]] = [:]
    for file in outOfDateFiles {
      guard let target = await buildSystemManager.canonicalConfiguredTarget(for: file.uri) else {
        logger.error("Not indexing \(file.uri.forLogging) because the target could not be determined")
        continue
      }
      filesByTarget[target, default: []].append(file)
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
      let taskID = UUID()
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
                await self.updateIndexStore(for: fileBatch, taskID: taskID, priority: priority)
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
        indexStatus[file.uri] = .scheduled((taskID, indexTask))
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
