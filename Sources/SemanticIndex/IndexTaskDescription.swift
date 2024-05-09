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

import SKCore

/// A task that either prepares targets or updates the index store for a set of files.
public enum IndexTaskDescription: TaskDescriptionProtocol {
  case updateIndexStore(UpdateIndexStoreTaskDescription)
  case preparation(PreparationTaskDescription)

  public var isIdempotent: Bool {
    switch self {
    case .updateIndexStore(let taskDescription): return taskDescription.isIdempotent
    case .preparation(let taskDescription): return taskDescription.isIdempotent
    }
  }

  public var estimatedCPUCoreCount: Int {
    switch self {
    case .updateIndexStore(let taskDescription): return taskDescription.estimatedCPUCoreCount
    case .preparation(let taskDescription): return taskDescription.estimatedCPUCoreCount
    }
  }

  public var id: String {
    switch self {
    case .updateIndexStore(let taskDescription): return "indexing-\(taskDescription.id)"
    case .preparation(let taskDescription): return "preparation-\(taskDescription.id)"
    }
  }

  public var description: String {
    switch self {
    case .updateIndexStore(let taskDescription): return taskDescription.description
    case .preparation(let taskDescription): return taskDescription.description
    }
  }

  public var redactedDescription: String {
    switch self {
    case .updateIndexStore(let taskDescription): return taskDescription.redactedDescription
    case .preparation(let taskDescription): return taskDescription.redactedDescription
    }
  }

  public func execute() async {
    switch self {
    case .updateIndexStore(let taskDescription): return await taskDescription.execute()
    case .preparation(let taskDescription): return await taskDescription.execute()
    }
  }

  /// Forward to the underlying task to compute the dependencies. Preparation and index tasks don't have any
  /// dependencies that are managed by `TaskScheduler`. `SemanticIndexManager` awaits the preparation of a target before
  /// indexing files within it.
  public func dependencies(
    to currentlyExecutingTasks: [IndexTaskDescription]
  ) -> [TaskDependencyAction<IndexTaskDescription>] {
    switch self {
    case .updateIndexStore(let taskDescription):
      let currentlyExecutingTasks =
        currentlyExecutingTasks
        .compactMap { (currentlyExecutingTask) -> UpdateIndexStoreTaskDescription? in
          if case .updateIndexStore(let currentlyExecutingTask) = currentlyExecutingTask {
            return currentlyExecutingTask
          }
          return nil
        }
      return taskDescription.dependencies(to: currentlyExecutingTasks).map {
        switch $0 {
        case .waitAndElevatePriorityOfDependency(let td):
          return .waitAndElevatePriorityOfDependency(.updateIndexStore(td))
        case .cancelAndRescheduleDependency(let td):
          return .cancelAndRescheduleDependency(.updateIndexStore(td))
        }
      }
    case .preparation(let taskDescription):
      let currentlyExecutingTasks =
        currentlyExecutingTasks
        .compactMap { (currentlyExecutingTask) -> PreparationTaskDescription? in
          if case .preparation(let currentlyExecutingTask) = currentlyExecutingTask {
            return currentlyExecutingTask
          }
          return nil
        }
      return taskDescription.dependencies(to: currentlyExecutingTasks).map {
        switch $0 {
        case .waitAndElevatePriorityOfDependency(let td):
          return .waitAndElevatePriorityOfDependency(.preparation(td))
        case .cancelAndRescheduleDependency(let td):
          return .cancelAndRescheduleDependency(.preparation(td))
        }
      }
    }
  }
}
