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
private enum FileIndexStatus {
  /// The index is up-to-date.
  case upToDate
  /// The file is being indexed by the given task.
  case inProgress(Task<Void, Never>)
}

/// Schedules index tasks and keeps track of the index status of files.
public final actor SemanticIndexManager {
  /// The underlying index. This is used to check if the index of a file is already up-to-date, in which case it doesn't
  /// need to be indexed again.
  private let index: CheckedIndex

  /// The build system manager that is used to get compiler arguments for a file.
  private let buildSystemManager: BuildSystemManager

  /// The index status of the source files that the `SemanticIndexManager` knows about.
  ///
  /// Files that have never been indexed are not in this dictionary.
  private var indexStatus: [DocumentURI: FileIndexStatus] = [:]

  /// The `TaskScheduler` that manages the scheduling of index tasks. This is shared among all `SemanticIndexManager`s
  /// in the process, to ensure that we don't schedule more index operations than processor cores from multiple
  /// workspaces.
  private let indexTaskScheduler: TaskScheduler<UpdateIndexStoreTaskDescription>

  /// Callback that is called when an index task has finished.
  ///
  /// Currently only used for testing.
  private let indexTaskDidFinish: (@Sendable (UpdateIndexStoreTaskDescription) -> Void)?

  // MARK: - Public API

  public init(
    index: UncheckedIndex,
    buildSystemManager: BuildSystemManager,
    indexTaskScheduler: TaskScheduler<UpdateIndexStoreTaskDescription>,
    indexTaskDidFinish: (@Sendable (UpdateIndexStoreTaskDescription) -> Void)?
  ) {
    self.index = index.checked(for: .modifiedFiles)
    self.buildSystemManager = buildSystemManager
    self.indexTaskScheduler = indexTaskScheduler
    self.indexTaskDidFinish = indexTaskDidFinish
  }

  /// Schedules a task to index all files in `files` that don't already have an up-to-date index.
  /// Returns immediately after scheduling that task.
  ///
  /// Indexing is being performed with a low priority.
  public func scheduleBackgroundIndex(files: some Collection<DocumentURI>) {
    self.index(files: files, priority: .low)
  }

  /// Wait for all in-progress index tasks to finish.
  public func waitForUpToDateIndex() async {
    logger.info("Waiting for up-to-date index")
    await withTaskGroup(of: Void.self) { taskGroup in
      for (_, status) in indexStatus {
        switch status {
        case .inProgress(let task):
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
    // Create a new index task for the files that aren't up-to-date. The newly scheduled index tasks will
    // - Wait for the existing index operations to finish if they have the same number of files.
    // - Reschedule the background index task in favor of an index task with fewer source files.
    await self.index(files: uris, priority: nil).value
    index.pollForUnitChangesAndWait()
    logger.debug("Done waiting for up-to-date index")
  }

  // MARK: - Helper functions

  /// Index the given set of files at the given priority.
  ///
  /// The returned task finishes when all files are indexed.
  @discardableResult
  private func index(files: some Collection<DocumentURI>, priority: TaskPriority?) -> Task<Void, Never> {
    let outOfDateFiles = files.filter {
      if case .upToDate = indexStatus[$0] {
        return false
      }
      return true
    }

    var indexTasks: [Task<Void, Never>] = []

    // TODO (indexing): Group index operations by target when we support background preparation.
    for files in outOfDateFiles.partition(intoNumberOfBatches: ProcessInfo.processInfo.processorCount * 5) {
      let indexTask = Task(priority: priority) {
        await self.indexTaskScheduler.schedule(
          priority: priority,
          UpdateIndexStoreTaskDescription(
            filesToIndex: Set(files),
            buildSystemManager: self.buildSystemManager,
            index: self.index,
            didFinishCallback: { [weak self] taskDescription in
              self?.indexTaskDidFinish?(taskDescription)
            }
          )
        ).value
        for file in files {
          indexStatus[file] = .upToDate
        }
      }
      indexTasks.append(indexTask)

      for file in files {
        indexStatus[file] = .inProgress(indexTask)
      }
    }
    let indexTasksImmutable = indexTasks

    return Task(priority: priority) {
      await withTaskGroup(of: Void.self) { taskGroup in
        for indexTask in indexTasksImmutable {
          taskGroup.addTask(priority: priority) {
            await indexTask.value
          }
        }
        await taskGroup.waitForAll()
      }
    }
  }
}
