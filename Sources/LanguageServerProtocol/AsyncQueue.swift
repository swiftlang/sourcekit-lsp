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

/// A serial queue that allows the execution of asyncronous blocks of code.
public final class AsyncQueue {
  /// Lock guarding `lastTask`.
  private let lastTaskLock = NSLock()

  /// The last scheduled task if it hasn't finished yet.
  ///
  /// Any newly scheduled tasks need to await this task to ensure that tasks are
  /// executed syncronously.
  ///
  /// `id` is a unique value to identify the task. This allows us to set `lastTask`
  /// to `nil` if the queue runs empty.
  private var lastTask: (task: AnyTask, id: UUID)?

  public init() {
    self.lastTaskLock.name = "AsyncQueue.lastTaskLock"
  }

  /// Schedule a new closure to be executed on the queue.
  ///
  /// All previously added tasks are guaranteed to finished executing before
  /// this closure gets executed.
  @discardableResult
  public func async<Success: Sendable>(
    priority: TaskPriority? = nil,
    @_inheritActorContext operation: @escaping @Sendable () async -> Success
  ) -> Task<Success, Never> {
    let id = UUID()

    return lastTaskLock.withLock {
      let task = Task<Success, Never>(priority: priority) { [previousLastTask = lastTask] in
        await previousLastTask?.task.waitForCompletion()

        defer {
          lastTaskLock.withLock {
            // If we haven't queued a new task since enquing this one, we can clear
            // last task.
            if self.lastTask?.id == id {
              self.lastTask = nil
            }
          }
        }

        return await operation()
      }

      lastTask = (task, id)

      return task
    }
  }
}
