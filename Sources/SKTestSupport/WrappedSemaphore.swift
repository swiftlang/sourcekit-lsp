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

import Dispatch
import XCTest

/// Wrapper around `DispatchSemaphore` so that Swift Concurrency doesn't complain about the usage of semaphores in the
/// tests.
///
/// This should only be used for tests that test priority escalation and thus cannot await a `Task` (which would cause
/// priority elevations).
package struct WrappedSemaphore: Sendable {
  private let name: String
  private let semaphore = DispatchSemaphore(value: 0)

  package init(name: String) {
    self.name = name
  }

  package func signal(value: Int = 1) {
    for _ in 0..<value {
      semaphore.signal()
    }
  }

  private func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
  }

  /// Wait for a signal and throw an error if the semaphore is not signaled within `timeout`.
  package func waitOrThrow(timeout: DispatchTime = DispatchTime.now() + .seconds(Int(defaultTimeout))) throws {
    struct TimeoutError: Error, CustomStringConvertible {
      let name: String
      var description: String { "\(name) timed out" }
    }
    switch self.wait(timeout: timeout) {
    case .success:
      break
    case .timedOut:
      throw TimeoutError(name: name)
    }
  }

  /// Wait for a signal and emit an XCTFail if the semaphore is not signaled within `timeout`.
  package func waitOrXCTFail(timeout: DispatchTime = DispatchTime.now() + .seconds(Int(defaultTimeout))) {
    switch self.wait(timeout: timeout) {
    case .success:
      break
    case .timedOut:
      XCTFail("\(name) timed out")
    }
  }
}
