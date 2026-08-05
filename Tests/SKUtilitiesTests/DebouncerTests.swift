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

import SKTestSupport
import SKUtilities
import XCTest

final class DebouncerTests: XCTestCase {
  func testDebouncerDebounces() async throws {
    let expectation = self.expectation(description: "makeCallCalled")
    expectation.assertForOverFulfill = true
    let debouncer = Debouncer<Void>(debounceDuration: .seconds(0.1)) {
      expectation.fulfill()
    }
    await debouncer.scheduleCall()
    await debouncer.scheduleCall()
    try await fulfillmentOfOrThrow(expectation)
    // Sleep for 0.2s to make sure the debouncer actually debounces and doesn't fulfill the expectation twice.
    try await Task.sleep(for: .seconds(0.2))
  }

  func testDebouncerCombinesParameters() async throws {
    let expectation = self.expectation(description: "makeCallCalled")
    expectation.assertForOverFulfill = true
    let debouncer = Debouncer<Int>(
      debounceDuration: .seconds(0.1),
      combineResults: { $0 + $1 },
      makeCall: { param in
        XCTAssertEqual(param, 3)
        expectation.fulfill()
      }
    )
    await debouncer.scheduleCall(1)
    await debouncer.scheduleCall(2)
    try await fulfillmentOfOrThrow(expectation)
  }

  /// Tests that the debounce deadline is fixed at the time of the first `scheduleCall` and not reset by subsequent
  /// calls. Subsequent calls within the debounce window should preserve the original deadline.
  func testDebouncerDeadlineIsNotResetBySubsequentCalls() async throws {
    let expectation = self.expectation(description: "makeCallCalled")
    expectation.assertForOverFulfill = true
    let debouncer = Debouncer<Void>(debounceDuration: .milliseconds(500)) {
      expectation.fulfill()
    }
    await debouncer.scheduleCall()  // deadline: now + 500ms
    try await Task.sleep(for: .milliseconds(100))
    await debouncer.scheduleCall()  // should keep the original deadline, not reset to now + 500ms
    try await Task.sleep(for: .milliseconds(100))
    await debouncer.scheduleCall()  // same

    // Fires -300ms from now (500ms from first call, 200ms already elapsed).
    try await fulfillmentOfOrThrow(expectation, timeout: 0.4)
  }

  /// Tests that a `makeCall` in progress is not cancelled when a new `scheduleCall` arrives.
  func testMakeCallIsNotCancelledBySubsequentScheduleCall() async throws {
    nonisolated(unsafe) var makeCallContinuation: CheckedContinuation<Void, Never>? = nil
    let makeCallStarted = self.expectation(description: "makeCallStarted")
    let makeCallCompleted = self.expectation(description: "makeCallCompleted")

    let debouncer = Debouncer<Void>(debounceDuration: .milliseconds(50)) {
      guard makeCallContinuation == nil else {
        return
      }
      // Pause makeCall and signal the test that it has started.
      await withCheckedContinuation { continuation in
        makeCallContinuation = continuation
        makeCallStarted.fulfill()
      }
      XCTAssertFalse(Task.isCancelled, "makeCall should run in a fresh, non-cancelled task")
      makeCallCompleted.fulfill()
    }

    await debouncer.scheduleCall()
    // Wait until makeCall has started executing.
    try await fulfillmentOfOrThrow(makeCallStarted)
    // Schedule another call while the first makeCall is suspended.
    await debouncer.scheduleCall()
    // Resume makeCall and verify it completes without being cancelled.
    makeCallContinuation!.resume()
    try await fulfillmentOfOrThrow(makeCallCompleted)
  }
}
