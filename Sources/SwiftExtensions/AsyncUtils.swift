//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) package import ToolsProtocolsSwiftExtensions

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
  var mutableTasks: [Task<Void, any Error>] = []
  let stream = AsyncThrowingStream<T, any Error> { continuation in
    let bodyTask = Task<Void, any Error>(priority: priority) {
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

package enum WithTimeoutResult<T> {
  case result(T)
  case timedOut
}

/// Executes `body`. If it doesn't finish after `duration`, return `.timed` and continue running body. When `body`
/// returns a value after the timeout, `resultReceivedAfterTimeout` is called.
///
/// - Important: `body` will not be cancelled when the timeout is received. Use the other overload of `withTimeout` if
///   `body` should be cancelled after `timeout`.
package func withTimeoutResult<T: Sendable>(
  _ timeout: Duration,
  body: @escaping @Sendable () async throws -> T,
  resultReceivedAfterTimeout: @escaping @Sendable (_ result: T) async -> Void
) async throws -> WithTimeoutResult<T> {
  let didHitTimeout = AtomicBool(initialValue: false)

  let stream = AsyncThrowingStream<WithTimeoutResult<T>, any Error> { continuation in
    Task {
      try await Task.sleep(for: timeout)
      didHitTimeout.value = true
      continuation.yield(.timedOut)
    }

    Task {
      do {
        let result = try await body()
        if didHitTimeout.value {
          await resultReceivedAfterTimeout(result)
        }
        continuation.yield(.result(result))
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

/// Executes `body`. If it doesn't finish after `duration`, return `nil` and continue running body. When `body` returns
/// a value after the timeout, `resultReceivedAfterTimeout` is called.
///
/// - Important: `body` will not be cancelled when the timeout is received. Use the other overload of `withTimeout` if
///   `body` should be cancelled after `timeout`.
package func withTimeout<T: Sendable>(
  _ timeout: Duration,
  body: @escaping @Sendable () async throws -> T,
  resultReceivedAfterTimeout: @escaping @Sendable (_ result: T) async -> Void
) async throws -> T? {
  let timeoutResult: WithTimeoutResult<T> = try await withTimeoutResult(
    timeout,
    body: body,
    resultReceivedAfterTimeout: resultReceivedAfterTimeout
  )
  switch timeoutResult {
  case .timedOut: return nil
  case .result(let result): return result
  }
}

/// Same as `withTimeout` above but allows `body` to return an optional value.
package func withTimeout<T: Sendable>(
  _ timeout: Duration,
  body: @escaping @Sendable () async throws -> T?,
  resultReceivedAfterTimeout: @escaping @Sendable (_ result: T?) async -> Void
) async throws -> T? {
  let result: T?? = try await withTimeout(timeout, body: body, resultReceivedAfterTimeout: resultReceivedAfterTimeout)
  switch result {
  case .none: return nil
  case .some(.none): return nil
  case .some(.some(let value)): return value
  }
}
