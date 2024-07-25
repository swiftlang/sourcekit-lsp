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
import SwiftExtensions
import XCTest

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
}
