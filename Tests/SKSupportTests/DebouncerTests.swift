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

import SKSupport
import SKTestSupport
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
    try await fulfillmentOfOrThrow([expectation])
    // Sleep for 0.2s to make sure the debouncer actually debounces and doesn't fulfill the expectation twice.
    try await Task.sleep(for: .seconds(0.2))
  }

  func testDebouncerCombinesParameters() async throws {
    let expectation = self.expectation(description: "makeCallCalled")
    expectation.assertForOverFulfill = true
    let debouncer = Debouncer<Int>(debounceDuration: .seconds(0.1), combineResults: { $0 + $1 }) { param in
      XCTAssertEqual(param, 3)
      expectation.fulfill()
    }
    await debouncer.scheduleCall(1)
    await debouncer.scheduleCall(2)
    try await fulfillmentOfOrThrow([expectation])
  }
}
