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

@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

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

  let stream = AsyncThrowingStream<WithTimeoutResult<T>, Error> { continuation in
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
