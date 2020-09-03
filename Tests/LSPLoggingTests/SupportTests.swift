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

import LSPLogging
import XCTest

final class SupportTests: XCTestCase {

  func testLogging() {
    let testLogger = Logger(disableOSLog: true, disableNSLog: true)

    var messages: [(String, LogLevel)] = []
    let obj = testLogger.addLogHandler { message, level in
      messages.append((message, level))
    }

    func check(expected: [(String, LogLevel)], file: StaticString = #filePath, line: UInt = #line) {
      testLogger.flush()
      XCTAssert(messages.count == expected.count, "\(messages) does not match expected \(expected)", file: file, line: line)
      XCTAssert(zip(messages, expected).allSatisfy({ $0.0 == $0.1 }), "\(messages) does not match expected \(expected)", file: file, line: line)
      messages.removeAll()
    }

    testLogger.currentLevel = .default

    testLogger.log("a")
    check(expected: [("a", .default)])
    check(expected: [])

    testLogger.log("b\n\nc")
    check(expected: [("b\n\nc", .default)])

    enum MyError: Error { case one }
    func throw1(_ x: Int) throws -> Int {
      if x == 1 { throw MyError.one }
      return x
    }

    XCTAssertEqual(orLog(logger: testLogger) { try throw1(0) }, 0)
    check(expected: [])
    XCTAssertNil(orLog(logger: testLogger) { try throw1(1) })
    check(expected: [("one", .default)])
    XCTAssertNil(orLog("hi", logger: testLogger) { try throw1(1) })
    check(expected: [("hi one", .default)])

    testLogger.logAsync { (currentLevel) -> String? in
      return "\(currentLevel)"
    }
    check(expected: [("info", .default)])

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ("e", .warning),
      ("f", .info),
      ])

    testLogger.currentLevel = .warning

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ("e", .warning),
      ])

    testLogger.currentLevel = .error

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ])

    testLogger.currentLevel = .default

    // .warning
    testLogger.setLogLevel("1")

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ("e", .warning),
      ])

    // .error
    testLogger.setLogLevel("0")

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ])

    // missing - no change
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_err")

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ])

    // invalid - no change
    testLogger.setLogLevel("")

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ])

    // invalid - no change
    testLogger.setLogLevel("a3")

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ])

    // too high - max out at .debug
    testLogger.setLogLevel("1000")

    testLogger.log("d", level: .error)
    testLogger.log("e", level: .warning)
    testLogger.log("f", level: .info)
    testLogger.log("g", level: .debug)
    check(expected: [
      ("d", .error),
      ("e", .warning),
      ("f", .info),
      ("g", .debug),
      ])

    // By string.
    testLogger.setLogLevel("error")
    XCTAssertEqual(testLogger.currentLevel, .error)
    testLogger.setLogLevel("warning")
    XCTAssertEqual(testLogger.currentLevel, .warning)
    testLogger.setLogLevel("info")
    XCTAssertEqual(testLogger.currentLevel, .info)
    testLogger.setLogLevel("debug")
    XCTAssertEqual(testLogger.currentLevel, .debug)

    testLogger.currentLevel = .default
    testLogger.addLogHandler(obj)

    testLogger.log("a")
    check(expected: [
      ("a", .default),
      ("a", .default),
      ])

    testLogger.removeLogHandler(obj)

    testLogger.log("a")
    check(expected: [])
  }
}
