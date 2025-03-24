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

import Foundation

/// Abstraction layer so we can store a heterogeneous collection of tasks in an
/// array.
private protocol AnyTask: Sendable {
  func waitForCompletion() async

  func cancel()
}

extension Task: AnyTask {
  func waitForCompletion() async {
    _ = try? await value
  }
}

/// A type that is able to track dependencies between tasks.
package protocol DependencyTracker: Sendable, Hashable {
  /// Whether the task described by `self` needs to finish executing before `other` can start executing.
  func isDependency(of other: Self) -> Bool
}

/// A dependency tracker where each task depends on every other, i.e. a serial
/// queue.
package struct Serial: DependencyTracker {
  package func isDependency(of other: Serial) -> Bool {
    return true
  }
}

package struct PendingTask<TaskMetadata: Sendable & Hashable>: Sendable {
  /// The task that is pending.
  fileprivate let task: any AnyTask

  /// A unique value used to identify the task. This allows tasks to get
  /// removed from `pendingTasks` again after they finished executing.
  fileprivate let id: UUID
}

/// A list of pending tasks that can be sent across actor boundaries and is guarded by a lock.
///
/// - Note: Unchecked sendable because the tasks are being protected by a lock.
private final class PendingTasks<TaskMetadata: Sendable & Hashable>: Sendable {
  ///  Lock guarding `pendingTasks`.
  private let lock = NSLock()

  /// Pending tasks that have not finished execution yet.
  ///
  /// - Important: This must only be accessed while `lock` has been acquired.
  private nonisolated(unsafe) var tasksByMetadata: [TaskMetadata: [PendingTask<TaskMetadata>]] = [:]

  init() {
    self.lock.name = "AsyncQueue"
  }

  /// Capture a lock and execute the closure, which may modify the pending tasks.
  func withLock<T>(
    _ body: (_ tasksByMetadata: inout [TaskMetadata: [PendingTask<TaskMetadata>]]) throws -> T
  ) rethrows -> T {
    try lock.withLock {
      try body(&tasksByMetadata)
    }
  }
}

/// A queue that allows the execution of asynchronous blocks of code.
package final class AsyncQueue<TaskMetadata: DependencyTracker>: Sendable {
  private let pendingTasks: PendingTasks<TaskMetadata> = PendingTasks()

  package init() {}

  /// Schedule a new closure to be executed on the queue.
  ///
  /// If this is a serial queue, all previously added tasks are guaranteed to
  /// finished executing before this closure gets executed.
  ///
  /// If this is a barrier, all previously scheduled tasks are guaranteed to
  /// finish execution before the barrier is executed and all tasks that are
  /// added later will wait until the barrier finishes execution.
  @discardableResult
  package func async<Success: Sendable>(
    priority: TaskPriority? = nil,
    metadata: TaskMetadata,
    @_inheritActorContext operation: @escaping @Sendable () async -> Success
  ) -> Task<Success, Never> {
    let throwingTask = asyncThrowing(priority: priority, metadata: metadata, operation: operation)
    return Task(priority: priority) {
      do {
        return try await throwingTask.valuePropagatingCancellation
      } catch {
        // We know this can never happen because `operation` does not throw.
        preconditionFailure("Executing a task threw an error even though the operation did not throw")
      }
    }
  }

  /// Same as ``AsyncQueue/async(priority:barrier:operation:)`` but allows the
  /// operation to throw.
  ///
  /// - Important: The caller is responsible for handling any errors thrown from
  ///   the operation by awaiting the result of the returned task.
  package func asyncThrowing<Success: Sendable>(
    priority: TaskPriority? = nil,
    metadata: TaskMetadata,
    @_inheritActorContext operation: @escaping @Sendable () async throws -> Success
  ) -> Task<Success, any Error> {
    let id = UUID()

    return pendingTasks.withLock { tasksByMetadata in
      // Build the list of tasks that need to finished execution before this one
      // can be executed
      var dependencies: [PendingTask<TaskMetadata>] = []
      for (pendingMetadata, pendingTasks) in tasksByMetadata {
        guard pendingMetadata.isDependency(of: metadata) else {
          // No dependency
          continue
        }
        if metadata.isDependency(of: metadata), let lastPendingTask = pendingTasks.last {
          // This kind of task depends on all other tasks of the same kind finishing. It is sufficient to just wait on
          // the last task with this metadata, it will have all the other tasks with the same metadata as transitive
          // dependencies.
          dependencies.append(lastPendingTask)
        } else {
          // We depend on tasks with this metadata, but they don't have any dependencies between them, eg.
          // `documentUpdate` depends on all `documentRequest` but `documentRequest` don't have dependencies between
          // them. We need to depend on all of them unless we knew that we depended on some other task that already
          // depends on all of these. But determining that would also require knowledge about the entire dependency
          // graph, which is likely as expensive as depending on all of these tasks.
          dependencies += pendingTasks
        }
      }

      // Schedule the task.
      let task = Task(priority: priority) { [pendingTasks] in
        // IMPORTANT: The only throwing call in here must be the call to
        // operation. Otherwise the assumption that the task will never throw
        // if `operation` does not throw, which we are making in `async` does
        // not hold anymore.
        for dependency in dependencies {
          await dependency.task.waitForCompletion()
        }

        let result = try await operation()

        pendingTasks.withLock { tasksByMetadata in
          tasksByMetadata[metadata, default: []].removeAll(where: { $0.id == id })
          if tasksByMetadata[metadata]?.isEmpty ?? false {
            tasksByMetadata[metadata] = nil
          }
        }

        return result
      }

      tasksByMetadata[metadata, default: []].append(PendingTask(task: task, id: id))

      return task
    }
  }
}

/// Convenience overloads for serial queues.
extension AsyncQueue where TaskMetadata == Serial {
  /// Same as ``async(priority:operation:)`` but specialized for serial queues
  /// that don't specify any metadata.
  @discardableResult
  package func async<Success: Sendable>(
    priority: TaskPriority? = nil,
    @_inheritActorContext operation: @escaping @Sendable () async -> Success
  ) -> Task<Success, Never> {
    return self.async(priority: priority, metadata: Serial(), operation: operation)
  }

  /// Same as ``asyncThrowing(priority:metadata:operation:)`` but specialized
  /// for serial queues that don't specify any metadata.
  package func asyncThrowing<Success: Sendable>(
    priority: TaskPriority? = nil,
    @_inheritActorContext operation: @escaping @Sendable () async throws -> Success
  ) -> Task<Success, any Error> {
    return self.asyncThrowing(priority: priority, metadata: Serial(), operation: operation)
  }
}
