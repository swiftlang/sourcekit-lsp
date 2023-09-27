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

import XCTest

/// Same as `assertNoThrow` but executes the trailing closure.
public func assertNoThrow<T>(
  _ expression: () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertNoThrow(try expression(), message(), file: file, line: line)
}

/// Same as `XCTAssertEqual` but doesn't take autoclosures and thus `expression1`
/// and `expression2` can contain `await`.
public func assertEqual<T: Equatable>(
  _ expression1: T,
  _ expression2: T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

extension XCTestCase {
  private struct ExpectationNotFulfilledError: Error, CustomStringConvertible {
    var expecatations: [XCTestExpectation]

    var description: String {
      return "One of the expectation was not fulfilled within timeout: \(expecatations.map(\.description).joined(separator: ", "))"
    }
  }

  /// Wait for the given expectations to be fulfilled. If the expectations aren't 
  /// fulfilled within `timeout`, throw an error, aborting the test execution.
  public func fulfillmentOfOrThrow(
    _ expectations: [XCTestExpectation],
    timeout: TimeInterval = defaultTimeout,
    enforceOrder enforceOrderOfFulfillment: Bool = false
  ) async throws {
    let started = await XCTWaiter.fulfillment(of: expectations, timeout: timeout, enforceOrder: enforceOrderOfFulfillment)
    if started != .completed {
      throw ExpectationNotFulfilledError(expecatations: expectations)
    }
  }
}
