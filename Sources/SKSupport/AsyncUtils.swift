//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Wrapper around a task that allows multiple clients to depend on the task's value.
///
/// If all of the dependents are cancelled, the underlying task is cancelled as well.
public actor RefCountedCancellableTask<Success> {
  public let task: Task<Success, Error>

  /// The number of clients that depend on the task's result and that are not cancelled.
  private var refCount: Int = 0

  /// Whether the task has been cancelled.
  public private(set) var isCancelled: Bool = false

  public init(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Success) {
    self.task = Task(priority: priority, operation: operation)
  }

  private func decrementRefCount() {
    refCount -= 1
    if refCount == 0 {
      self.cancel()
    }
  }

  /// Get the task's value.
  ///
  /// If all callers of `value` are cancelled, the underlying task gets cancelled as well.
  public var value: Success {
    get async throws {
      if isCancelled {
        throw CancellationError()
      }
      refCount += 1
      return try await withTaskCancellationHandler {
        return try await task.value
      } onCancel: {
        Task {
          await self.decrementRefCount()
        }
      }
    }
  }

  /// Cancel the task and throw a `CancellationError` to all clients that are awaiting the value.
  public func cancel() {
    isCancelled = true
    task.cancel()
  }
}

public extension Task {
  /// Awaits the value of the result.
  ///
  /// If the current task is cancelled, this will cancel the subtask as well.
  var valuePropagatingCancellation: Success {
    get async throws {
      try await withTaskCancellationHandler {
        return try await self.value
      } onCancel: {
        self.cancel()
      }
    }
  }
}

/// Allows the execution of a cancellable operation that returns the results
/// via a completion handler.
///
/// `operation` must invoke the continuation's `resume` method exactly once.
///
/// If the task executing `withCancellableCheckedThrowingContinuation` gets
/// cancelled, `cancel` is invoked with the handle that `operation` provided.
public func withCancellableCheckedThrowingContinuation<Handle, Result>(
  _ operation: (_ continuation: CheckedContinuation<Result, any Error>) -> Handle,
  cancel: (Handle) -> Void
) async throws -> Result {
  let handleWrapper = ThreadSafeBox<Handle?>(initialValue: nil)

  @Sendable
  func callCancel() {
    /// Take the request ID out of the box. This ensures that we only send the
    /// cancel notification once in case the `Task.isCancelled` and the
    /// `onCancel` check race.
    if let handle = handleWrapper.takeValue() {
      cancel(handle)
    }
  }

  return try await withTaskCancellationHandler(
    operation: {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        handleWrapper.value = operation(continuation)

        // Check if the task was cancelled. This ensures we send a
        // CancelNotification even if the task gets cancelled after we register
        // the cancellation handler but before we set the `requestID`.
        if Task.isCancelled {
          callCancel()
        }
      }
    },
    onCancel: callCancel
  )
}

extension Collection {
  /// Transforms all elements in the collection concurrently and returns the transformed collection.
  public func concurrentMap<TransformedElement>(
    maxConcurrentTasks: Int = ProcessInfo.processInfo.processorCount,
    _ transform: @escaping (Element) async -> TransformedElement
  ) async -> [TransformedElement] {
    let indexedResults = await withTaskGroup(of: (index: Int, element: TransformedElement).self) { taskGroup in
      var indexedResults: [(index: Int, element: TransformedElement)] = []
      for (index, element) in self.enumerated() {
        if index >= maxConcurrentTasks {
          // Wait for one item to finish being transformed so we don't exceed the maximum number of concurrent tasks.
          if let (index, transformedElement) = await taskGroup.next() {
            indexedResults.append((index, transformedElement))
          }
        }
        taskGroup.addTask {
          return (index, await transform(element))
        }
      }

      // Wait for all remaining elements to be transformed.
      for await (index, transformedElement) in taskGroup {
        indexedResults.append((index, transformedElement))
      }
      return indexedResults
    }
    return Array<TransformedElement>(unsafeUninitializedCapacity: indexedResults.count) { buffer, count in
      for (index, transformedElement) in indexedResults {
        (buffer.baseAddress! + index).initialize(to: transformedElement)
      }
      count = indexedResults.count
    }
  }
}
