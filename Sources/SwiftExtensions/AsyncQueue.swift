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
package protocol DependencyTracker: Sendable {
  /// Whether the task described by `self` needs to finish executing before
  /// `other` can start executing.
  func isDependency(of other: Self) -> Bool
}

/// A dependency tracker where each task depends on every other, i.e. a serial
/// queue.
package struct Serial: DependencyTracker {
  package func isDependency(of other: Serial) -> Bool {
    return true
  }
}

private struct PendingTask<TaskMetadata: Sendable>: Sendable {
  /// The task that is pending.
  let task: any AnyTask

  let metadata: TaskMetadata

  /// A unique value used to identify the task. This allows tasks to get
  /// removed from `pendingTasks` again after they finished executing.
  let id: UUID
}

/// A list of pending tasks that can be sent across actor boundaries and is guarded by a lock.
///
/// - Note: Unchecked sendable because the tasks are being protected by a lock.
private class PendingTasks<TaskMetadata: Sendable>: @unchecked Sendable {
  ///  Lock guarding `pendingTasks`.
  private let lock = NSLock()

  /// Pending tasks that have not finished execution yet.
  ///
  /// - Important: This must only be accessed while `lock` has been acquired.
  private var tasks: [PendingTask<TaskMetadata>] = []

  init() {
    self.lock.name = "AsyncQueue"
  }

  /// Capture a lock and execute the closure, which may modify the pending tasks.
  func withLock<T>(_ body: (_ pendingTasks: inout [PendingTask<TaskMetadata>]) throws -> T) rethrows -> T {
    try lock.withLock {
      try body(&tasks)
    }
  }
}

/// A queue that allows the execution of asynchronous blocks of code.
package final class AsyncQueue<TaskMetadata: DependencyTracker>: Sendable {
  private let pendingTasks: PendingTasks<TaskMetadata> = PendingTasks()

  package init() {}

  package func cancelTasks(where filter: (TaskMetadata) -> Bool) {
    pendingTasks.withLock { pendingTasks in
      for task in pendingTasks {
        if filter(task.metadata) {
          task.task.cancel()
        }
      }
    }
  }

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

    return pendingTasks.withLock { tasks in
      // Build the list of tasks that need to finished execution before this one
      // can be executed
      let dependencies: [PendingTask] = tasks.filter { $0.metadata.isDependency(of: metadata) }

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

        pendingTasks.withLock { tasks in
          tasks.removeAll(where: { $0.id == id })
        }

        return result
      }

      tasks.append(PendingTask(task: task, metadata: metadata, id: id))

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
