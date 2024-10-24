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

import SKLogging
import SKSupport
import SKTestSupport
import SwiftExtensions
import XCTest

#if os(Windows)
import WinSDK
#endif

final class AsyncUtilsTests: XCTestCase {
  func testWithTimeout() async throws {
    let expectation = self.expectation(description: "withTimeout body finished")
    await assertThrowsError(
      try await withTimeout(.seconds(0.1)) {
        try? await Task.sleep(for: .seconds(10))
        XCTAssert(Task.isCancelled)
        expectation.fulfill()
      }
    ) { error in
      XCTAssert(error is TimeoutError, "Received unexpected error \(error)")
    }
    try await fulfillmentOfOrThrow([expectation])
  }

  func testWithTimeoutReturnsImmediatelyEvenIfBodyDoesntCooperateInCancellation() async throws {
    let start = Date()
    await assertThrowsError(
      try await withTimeout(.seconds(0.1)) {
        #if os(Windows)
        Sleep(10_000 /*ms*/)
        #else
        sleep(10 /*s*/)
        #endif
      }
    ) { error in
      XCTAssert(error is TimeoutError, "Received unexpected error \(error)")
    }
    XCTAssert(Date().timeIntervalSince(start) < 5)
  }

  func testWithTimeoutEscalatesPriority() async throws {
    let expectation = self.expectation(description: "Timeout started")
    let task = Task(priority: .background) {
      // We don't actually hit the timeout. It's just a large value.
      try await withTimeout(.seconds(defaultTimeout * 2)) {
        expectation.fulfill()
        try await repeatUntilExpectedResult(sleepInterval: .seconds(0.1)) {
          logger.debug("Current priority: \(Task.currentPriority.rawValue)")
          return Task.currentPriority > .background
        }
      }
    }
    try await fulfillmentOfOrThrow([expectation])
    try await Task(priority: .high) {
      try await task.value
    }.value
  }
}
