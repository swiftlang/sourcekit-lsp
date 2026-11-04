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

package import Testing
package import XCTest

package func recordFailure(
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  if Test.current != nil {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
  } else {
    XCTFail(message, file: file, line: line)
  }
}

package func requireNonNil<T>(
  _ value: T?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> T {
  if Test.current != nil {
    let message = message()
    return try #require(
      value,
      message.isEmpty ? nil : Comment(rawValue: message),
      sourceLocation: sourceLocation
    )
  }
  return try XCTUnwrap(value, message(), file: file, line: line)
}

package func skipTest(
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Never {
  if Test.current != nil {
    try Test.cancel(Comment(rawValue: message), sourceLocation: sourceLocation)
  }
  throw XCTSkip(message, file: file, line: line)
}

/// Same as `XCTAssertNoThrow` but executes the trailing closure.
package func assertNoThrow<T>(
  _ expression: () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    _ = try expression()
  } catch {
    recordFailure(
      failureMessage("Expression was not expected to throw but threw \(error)", message()),
      file: file,
      line: line
    )
  }
}

/// Same as `assertNoThrow` but allows the closure to be `async`.
package func assertNoThrow<T>(
  _ expression: () async throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
  } catch {
    recordFailure(
      failureMessage("Expression was not expected to throw but threw \(error)", message()),
      file: file,
      line: line
    )
  }
}

/// Same as `XCTAssertThrows` but allows the expression to be async
package func assertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line,
  errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
  let didThrow: Bool
  do {
    _ = try await expression()
    didThrow = false
  } catch {
    errorHandler(error)
    didThrow = true
  }
  if !didThrow {
    recordFailure(
      failureMessage("Expression was expected to throw but did not throw", message()),
      file: file,
      line: line
    )
  }
}

/// Asserts that executing `expression` throws an error and that the error's string representation matches `expectedMessage`.
public func assertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  expectedMessage: Regex<Substring>,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  await assertThrowsError(try await expression(), file: file, line: line) { error in
    let errorString = String(reflecting: error)
    if try! expectedMessage.firstMatch(in: errorString) == nil {
      recordFailure(
        "Expected error to contain '\(expectedMessage)' but received '\(errorString)'",
        file: file,
        line: line
      )
    }
  }
}

/// Same as `XCTAssertEqual` but doesn't take autoclosures and thus `expression1`
/// and `expression2` can contain `await`.
package func assertEqual<T: Equatable>(
  _ expression1: T,
  _ expression2: T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if expression1 != expression2 {
    recordFailure(
      failureMessage("(\"\(expression1)\") is not equal to (\"\(expression2)\")", message()),
      file: file,
      line: line
    )
  }
}

/// Same as `XCTAssertTrue` but doesn't take autoclosures and thus `expression` can contain `await`.
package func assertTrue(
  _ expression: Bool,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if !expression {
    recordFailure(failureMessage("Expected true", message()), file: file, line: line)
  }
}

/// Same as `XCTAssertNil` but doesn't take autoclosures and thus `expression`
/// can contain `await`.
package func assertNil<T>(
  _ expression: T?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if let expression {
    recordFailure(failureMessage("(\"\(expression)\") is not nil", message()), file: file, line: line)
  }
}

/// Same as `XCTAssertNotNil` but doesn't take autoclosures and thus `expression`
/// can contain `await`.
package func assertNotNil<T>(
  _ expression: T?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if expression == nil {
    recordFailure(failureMessage("Expected non-nil value of type \(T.self)", message()), file: file, line: line)
  }
}

/// Check that the string contains the given substring.
package func assertContains(
  _ string: some StringProtocol,
  _ substring: some StringProtocol,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if !string.contains(substring) {
    recordFailure("Expected to contain '\(substring)': \(string)", file: file, line: line)
  }
}

/// Check that the sequence contains the given element.
package func assertContains<Element: Equatable>(
  _ sequence: some Sequence<Element>,
  _ element: Element,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if !sequence.contains(element) {
    recordFailure("Expected to contain '\(element)': \(sequence)", file: file, line: line)
  }
}

/// Same as `XCTUnwrap` but doesn't take autoclosures and thus `expression`
/// can contain `await`.
package func unwrap<T>(
  _ expression: T?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> T {
  return try requireNonNil(expression, message(), file: file, line: line)
}

private func failureMessage(_ failure: String, _ message: String) -> String {
  if message.isEmpty {
    return failure
  }
  return "\(failure) - \(message)"
}

package struct ExpectationNotFulfilledError: Error, CustomStringConvertible {
  var expectations: [XCTestExpectation]

  package var description: String {
    return """
      One of the expectation was not fulfilled within timeout: \
      \(expectations.map(\.description).joined(separator: ", "))
      """
  }
}

/// Wait for the given expectations to be fulfilled. If the expectations aren't
/// fulfilled within `timeout`, throw an error, aborting the test execution.
package nonisolated func fulfillmentOfOrThrow(
  _ expectations: XCTestExpectation...,
  timeout: TimeInterval = defaultTimeout,
  enforceOrder enforceOrderOfFulfillment: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  // `XCTWaiter.fulfillment` was introduced in the macOS 13.3 SDK but marked as being available on macOS 10.15.
  // At the same time that XCTWaiter.fulfillment was introduced `XCTWaiter.wait` was deprecated in async contexts.
  // This means that we can't write code that compiles without warnings with both the macOS 13.3 and any previous SDK.
  // Accepting the warning here when compiling with macOS 13.3 or later is the only thing that I know of that we can do here.
  let started = await XCTWaiter.fulfillment(
    of: expectations,
    timeout: timeout,
    enforceOrder: enforceOrderOfFulfillment
  )
  if started != .completed {
    // XCTFail because XCTest only reports the last-thrown error even if it's swallowed by `try?` etc.
    // This can happen e.g. when errors are thrown and swallowed in a `defer` block or `deinit`.
    XCTFail("Expectation '\(expectations)' not fulfilled", file: file, line: line)
    throw ExpectationNotFulfilledError(expectations: expectations)
  }
}
