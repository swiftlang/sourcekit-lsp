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
package actor RefCountedCancellableTask<Success: Sendable> {
  package let task: Task<Success, Error>

  /// The number of clients that depend on the task's result and that are not cancelled.
  private var refCount: Int = 0

  /// Whether the task has been cancelled.
  package private(set) var isCancelled: Bool = false

  package init(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Success) {
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
  package var value: Success {
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
  package func cancel() {
    isCancelled = true
    task.cancel()
  }
}

package extension Task {
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

package extension Task where Failure == Never {
  /// Awaits the value of the result.
  ///
  /// If the current task is cancelled, this will cancel the subtask as well.
  var valuePropagatingCancellation: Success {
    get async {
      await withTaskCancellationHandler {
        return await self.value
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
package func withCancellableCheckedThrowingContinuation<Handle: Sendable, Result>(
  _ operation: (_ continuation: CheckedContinuation<Result, any Error>) -> Handle,
  cancel: @Sendable (Handle) -> Void
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

extension Collection where Element: Sendable {
  /// Transforms all elements in the collection concurrently and returns the transformed collection.
  package func concurrentMap<TransformedElement: Sendable>(
    maxConcurrentTasks: Int = ProcessInfo.processInfo.processorCount,
    _ transform: @escaping @Sendable (Element) async -> TransformedElement
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

  /// Invoke `body` for every element in the collection and wait for all calls of `body` to finish
  package func concurrentForEach(_ body: @escaping @Sendable (Element) async -> Void) async {
    await withTaskGroup(of: Void.self) { taskGroup in
      for element in self {
        taskGroup.addTask {
          await body(element)
        }
      }
    }
  }
}

package struct TimeoutError: Error, CustomStringConvertible {
  package var description: String { "Timed out" }

  package let handle: TimeoutHandle?

  package init(handle: TimeoutHandle?) {
    self.handle = handle
  }
}

package final class TimeoutHandle: Equatable, Sendable {
  package init() {}

  static package func == (_ lhs: TimeoutHandle, _ rhs: TimeoutHandle) -> Bool {
    return lhs === rhs
  }
}

/// Executes `body`. If it doesn't finish after `duration`, throws a `TimeoutError` and cancels `body`.
///
/// `TimeoutError` is thrown immediately an the function does not wait for `body` to honor the cancellation.
///
/// If a `handle` is passed in and this `withTimeout` call times out, the thrown `TimeoutError` contains this handle.
/// This way a caller can identify whether this call to `withTimeout` timed out or if a nested call timed out.
package func withTimeout<T: Sendable>(
  _ duration: Duration,
  handle: TimeoutHandle? = nil,
  _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
  // Get the priority with which to launch the body task here so that we can pass the same priority as the initial
  // priority to `withTaskPriorityChangedHandler`. Otherwise, we can get into a race condition where bodyTask gets
  // launched with a low priority, then the priority gets elevated before we call with `withTaskPriorityChangedHandler`,
  // we thus don't receive a `taskPriorityChanged` and hence never increase the priority of `bodyTask`.
  let priority = Task.currentPriority
  var mutableTasks: [Task<Void, Error>] = []
  let stream = AsyncThrowingStream<T, Error> { continuation in
    let bodyTask = Task<Void, Error>(priority: priority) {
      do {
        let result = try await body()
        continuation.yield(result)
      } catch {
        continuation.yield(with: .failure(error))
      }
    }

    let timeoutTask = Task(priority: priority) {
      try await Task.sleep(for: duration)
      continuation.yield(with: .failure(TimeoutError(handle: handle)))
      bodyTask.cancel()
    }
    mutableTasks = [bodyTask, timeoutTask]
  }

  let tasks = mutableTasks

  defer {
    // Be extra careful and ensure that we don't leave `bodyTask` or `timeoutTask` running when `withTimeout` finishes,
    // eg. if `withTaskPriorityChangedHandler` adds some behavior that never executes `body` if the task gets cancelled.
    for task in tasks {
      task.cancel()
    }
  }

  return try await withTaskPriorityChangedHandler(initialPriority: priority) {
    for try await value in stream {
      return value
    }
    // The only reason for the loop above to terminate is if the Task got cancelled or if the stream finishes
    // (which it never does).
    if Task.isCancelled {
      // Throwing a `CancellationError` will make us return from `withTimeout`. We will cancel the `bodyTask` from the
      // `defer` method above.
      throw CancellationError()
    } else {
      preconditionFailure("Continuation never finishes")
    }
  } taskPriorityChanged: {
    for task in tasks {
      Task(priority: Task.currentPriority) {
        _ = try? await task.value
      }
    }
  }
}

/// Executes `body`. If it doesn't finish after `duration`, return `nil` and continue running body. When `body` returns
/// a value after the timeout, `resultReceivedAfterTimeout` is called.
///
/// - Important: `body` will not be cancelled when the timeout is received. Use the other overload of `withTimeout` if
///   `body` should be cancelled after `timeout`.
package func withTimeout<T: Sendable>(
  _ timeout: Duration,
  body: @escaping @Sendable () async throws -> T?,
  resultReceivedAfterTimeout: @escaping @Sendable () async -> Void
) async throws -> T? {
  let didHitTimeout = AtomicBool(initialValue: false)

  let stream = AsyncThrowingStream<T?, Error> { continuation in
    Task {
      try await Task.sleep(for: timeout)
      didHitTimeout.value = true
      continuation.yield(nil)
    }

    Task {
      do {
        let result = try await body()
        if didHitTimeout.value {
          await resultReceivedAfterTimeout()
        }
        continuation.yield(result)
      } catch {
        continuation.yield(with: .failure(error))
      }
    }
  }

  for try await value in stream {
    return value
  }
  // The only reason for the loop above to terminate is if the Task got cancelled or if the continuation finishes
  // (which it never does).
  if Task.isCancelled {
    throw CancellationError()
  } else {
    preconditionFailure("Continuation never finishes")
  }
}
