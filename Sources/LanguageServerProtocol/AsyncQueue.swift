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
}

extension Task: AnyTask where Failure == Never {
  func waitForCompletion() async {
    _ = await value
  }
}

extension NSLock {
  /// NOTE: Keep in sync with SwiftPM's 'Sources/Basics/NSLock+Extensions.swift'
  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

/// A queue that allows the execution of asyncronous blocks of code.
public final class AsyncQueue {
  public enum QueueKind {
    /// A queue that allows concurrent execution of tasks.
    case concurrent

    /// A queue that executes one task after the other.
    case serial
  }

  private struct PendingTask {
    /// The task that is pending.
    let task: any AnyTask

    /// Whether the task needs to finish executing befoer any other task can
    /// start in executing in the queue.
    let isBarrier: Bool

    /// A unique value used to identify the task. This allows tasks to get
    /// removed from `pendingTasks` again after they finished executing.
    let id: UUID
  }

  /// Whether the queue allows concurrent execution of tasks.
  private let kind: QueueKind

  ///  Lock guarding `pendingTasks`.
  private let pendingTasksLock = NSLock()

  /// Pending tasks that have not finished execution yet.
  private var pendingTasks = [PendingTask]()

  public init(_ kind: QueueKind) {
    self.kind = kind
    self.pendingTasksLock.name = "AsyncQueue"
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
  public func async<Success: Sendable>(
    priority: TaskPriority? = nil,
    barrier isBarrier: Bool = false,
    @_inheritActorContext operation: @escaping @Sendable () async -> Success
  ) -> Task<Success, Never> {
    let id = UUID()

    return pendingTasksLock.withLock {
      // Build the list of tasks that need to finishe exeuction before this one
      // can be executed
      let dependencies: [PendingTask]
      switch (kind, isBarrier: isBarrier) {
      case (.concurrent, isBarrier: true):
        // Wait for all tasks after the last barrier.
        let lastBarrierIndex = pendingTasks.lastIndex(where: { $0.isBarrier }) ?? pendingTasks.startIndex
        dependencies = Array(pendingTasks[lastBarrierIndex...])
      case (.concurrent, isBarrier: false):
        // If there is a barrier, wait for it.
        dependencies = [pendingTasks.last(where: { $0.isBarrier })].compactMap { $0 }
      case (.serial, _):
        // We are in a serial queue. The last pending task must finish for this one to start.
        dependencies = [pendingTasks.last].compactMap { $0 }
      }


      // Schedule the task.
      let task = Task {
        for dependency in dependencies {
          await dependency.task.waitForCompletion()
        }

        let result = await operation()

        pendingTasksLock.withLock {
          pendingTasks.removeAll(where: { $0.id == id })
        }

        return result
      }

      pendingTasks.append(PendingTask(task: task, isBarrier: isBarrier, id: id))

      return task
    }
  }
}
