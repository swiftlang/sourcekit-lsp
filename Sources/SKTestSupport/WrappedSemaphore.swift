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

/// Wrapper around `DispatchSemaphore` so that Swift Concurrency doesn't complain about the usage of semaphores in the
/// tests.
///
/// This should only be used for tests that test priority escalation and thus cannot await a `Task` (which would cause
/// priority elevations).
public struct WrappedSemaphore {
  let semaphore = DispatchSemaphore(value: 0)

  public init() {}

  public func signal(value: Int = 1) {
    for _ in 0..<value {
      semaphore.signal()
    }
  }

  public func wait(value: Int = 1) {
    for _ in 0..<value {
      semaphore.wait()
    }
  }
}
