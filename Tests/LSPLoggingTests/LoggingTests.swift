//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import LSPLogging
import SKTestSupport
import XCTest

fileprivate func assertLogging(
  logLevel: NonDarwinLogLevel = .default,
  privacyLevel: NonDarwinLogPrivacy = .private,
  expected: [String],
  _ body: (NonDarwinLogger) -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  var messages: [String] = []
  let logger = NonDarwinLogger(
    subsystem: subsystem,
    category: "test",
    logLevel: logLevel,
    privacyLevel: privacyLevel,
    logHandler: { messages.append($0) }
  )
  body(logger)
  NonDarwinLogger.flush()
  guard messages.count == expected.count else {
    XCTFail(
      """
      Number of messages does not match expected does not match expected

      Received:
      \(messages.joined(separator: "\n"))
      """,
      file: file,
      line: line
    )
    return
  }
  for (message, expected) in zip(messages, expected) {
    guard let firstNewline = message.firstIndex(of: "\n") else {
      XCTFail(
        """
        Did not find newline separating header from message in
        \(message)
        """,
        file: file,
        line: line
      )
      continue
    }
    guard message.hasSuffix("\n---") else {
      XCTFail("Message is expected to end with `---`", file: file, line: line)
      return
    }
    let messageContent = String(message[message.index(after: firstNewline)...].dropLast(4))
    XCTAssertEqual(messageContent, expected, "Message does not match expected", file: file, line: line)
  }

  messages.removeAll()
}

final class LoggingTests: XCTestCase {
  func testLoggingFormat() async throws {
    let expectation = self.expectation(description: "message logged")
    var message: String = ""
    let logger = NonDarwinLogger(
      subsystem: subsystem,
      category: "test",
      logHandler: {
        message = $0
        expectation.fulfill()
      }
    )
    logger.log(level: .error, "my message")
    try await fulfillmentOfOrThrow([expectation])
    XCTAssert(
      message.starts(with: "[org.swift.sourcekit-lsp:test] error"),
      "Message did not have expected header. Received \n\(message)"
    )
    XCTAssert(message.hasSuffix("\nmy message\n---"), "Message did not have expected body. Received \n\(message)")
  }

  func testLoggingBasic() {
    assertLogging(
      expected: ["a"],
      {
        $0.log("a")
      }
    )

    assertLogging(
      expected: [],
      { _ in
      }
    )

    assertLogging(expected: ["b\n\nc"]) {
      $0.log("b\n\nc")
    }
  }

  func testLogLevels() {
    assertLogging(
      logLevel: .default,
      expected: ["d", "e", "f"]
    ) {
      $0.fault("d")
      $0.error("e")
      $0.log("f")
      $0.info("g")
      $0.debug("h")
    }

    assertLogging(
      logLevel: .error,
      expected: ["d", "e"]
    ) {
      $0.fault("d")
      $0.error("e")
      $0.log("f")
      $0.info("g")
      $0.debug("h")
    }

    assertLogging(
      logLevel: .fault,
      expected: ["d"]
    ) {
      $0.fault("d")
      $0.error("e")
      $0.log("f")
      $0.info("g")
      $0.debug("h")
    }
  }

  func testPrivacyMaskingLevels() {
    assertLogging(expected: ["password is <private>"]) {
      let password: String = "1234"
      $0.log("password is \(password, privacy: .sensitive)")
    }

    assertLogging(expected: ["username is root"]) {
      let username: String = "root"
      $0.log("username is \(username, privacy: .private)")
    }

    assertLogging(expected: ["username is root"]) {
      let username: String = "root"
      $0.log("username is \(username)")
    }

    assertLogging(
      privacyLevel: .public,
      expected: ["username is <private>"]
    ) {
      let username: String = "root"
      $0.log("username is \(username, privacy: .private)")
    }

    assertLogging(
      privacyLevel: .public,
      expected: ["username is <private>"]
    ) {
      let username: String = "root"
      $0.log("username is \(username)")
    }
  }

  func testPrivacyMaskingTypes() {
    assertLogging(
      privacyLevel: .public,
      expected: ["logging a static string"]
    ) {
      $0.log("logging a \("static string")")
    }

    assertLogging(
      privacyLevel: .public,
      expected: ["logging from LSPLoggingTests.LoggingTests"]
    ) {
      $0.log("logging from \(LoggingTests.self)")
    }

    struct LogStringConvertible: CustomLogStringConvertible {
      var description: String = "full description"
      var redactedDescription: String = "redacted description"
    }

    assertLogging(
      privacyLevel: .public,
      expected: ["got redacted description"]
    ) {
      $0.log("got \(LogStringConvertible().forLogging)")
    }

    assertLogging(
      privacyLevel: .private,
      expected: ["got full description"]
    ) {
      $0.log("got \(LogStringConvertible().forLogging)")
    }
  }
}
