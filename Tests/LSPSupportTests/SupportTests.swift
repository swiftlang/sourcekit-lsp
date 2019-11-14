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

import LSPSupport
import XCTest

final class SupportTests: XCTestCase {

  func testResultEquality() {
    enum MyError: Error, Equatable {
      case err1, err2
    }
    typealias MyResult<T> = Swift.Result<T, MyError>

    XCTAssertEqual(MyResult.success(1), .success(1))
    XCTAssertNotEqual(MyResult.success(2), .success(1))
    XCTAssertNotEqual(MyResult.failure(.err1), .success(1))
    XCTAssertEqual(MyResult.failure(.err1), MyResult<Int>.failure(.err1))
    XCTAssertNotEqual(MyResult.failure(.err1), MyResult<Int>.failure(.err2))
  }

  func testResultProjection() {
    enum MyError: Error, Equatable {
      case err1, err2
    }
    typealias MyResult<T> = Swift.Result<T, MyError>

    XCTAssertEqual(MyResult.success(1).success, 1)
    XCTAssertNil(MyResult.failure(.err1).success)
    XCTAssertNil(MyResult.success(1).failure)
    XCTAssertEqual(MyResult<Int>.failure(.err1).failure, .err1)
  }

  func testIntFromAscii() {
    XCTAssertNil(Int(ascii: ""))
    XCTAssertNil(Int(ascii: "a"))
    XCTAssertNil(Int(ascii: "0x1"))
    XCTAssertNil(Int(ascii: " "))
    XCTAssertNil(Int(ascii: "+"))
    XCTAssertNil(Int(ascii: "-"))
    XCTAssertNil(Int(ascii: "+ "))
    XCTAssertNil(Int(ascii: "- "))
    XCTAssertNil(Int(ascii: "1 1"))
    XCTAssertNil(Int(ascii: "1a1"))
    XCTAssertNil(Int(ascii: "1a"))
    XCTAssertNil(Int(ascii: "1+"))
    XCTAssertNil(Int(ascii: "+ 1"))
    XCTAssertNil(Int(ascii: "- 1"))
    XCTAssertNil(Int(ascii: "1-1"))

    XCTAssertEqual(Int(ascii: "0"), 0)
    XCTAssertEqual(Int(ascii: "1"), 1)
    XCTAssertEqual(Int(ascii: "45"), 45)
    XCTAssertEqual(Int(ascii: "     45    "), 45)
    XCTAssertEqual(Int(ascii: "\(Int.max)"), Int.max)
    XCTAssertEqual(Int(ascii: "\(Int.max-1)"), Int.max-1)
    XCTAssertEqual(Int(ascii: "\(Int.min)"), Int.min)
    XCTAssertEqual(Int(ascii: "\(Int.min+1)"), Int.min+1)

    XCTAssertEqual(Int(ascii: "+0"), 0)
    XCTAssertEqual(Int(ascii: "+1"), 1)
    XCTAssertEqual(Int(ascii: "+45"), 45)
    XCTAssertEqual(Int(ascii: "     +45    "), 45)
    XCTAssertEqual(Int(ascii: "-0"), 0)
    XCTAssertEqual(Int(ascii: "-1"), -1)
    XCTAssertEqual(Int(ascii: "-45"), -45)
    XCTAssertEqual(Int(ascii: "     -45    "), -45)
    XCTAssertEqual(Int(ascii: "+\(Int.max)"), Int.max)
    XCTAssertEqual(Int(ascii: "+\(Int.max-1)"), Int.max-1)
    XCTAssertEqual(Int(ascii: "\(Int.min)"), Int.min)
    XCTAssertEqual(Int(ascii: "\(Int.min+1)"), Int.min+1)
  }

  func testFindSubsequence() {
    XCTAssertNil([0, 1, 2].firstIndex(of: [3]))
    XCTAssertNil([].firstIndex(of: [3]))
    XCTAssertNil([0, 1, 2].firstIndex(of: [1, 3]))
    XCTAssertNil([0, 1, 2].firstIndex(of: [0, 2]))
    XCTAssertNil([0, 1, 2].firstIndex(of: [2, 3]))
    XCTAssertNil([0, 1].firstIndex(of: [1, 0]))
    XCTAssertNil([0].firstIndex(of: [0, 1]))

    XCTAssertEqual([Int]().firstIndex(of: []), 0)
    XCTAssertEqual([0].firstIndex(of: []), 0)
    XCTAssertEqual([0].firstIndex(of: [0]), 0)
    XCTAssertEqual([0, 1].firstIndex(of: [0]), 0)
    XCTAssertEqual([0, 1].firstIndex(of: [1]), 1)

    XCTAssertEqual([0, 1].firstIndex(of: [0, 1]), 0)
    XCTAssertEqual([0, 1, 2, 3].firstIndex(of: [0, 1]), 0)
    XCTAssertEqual([0, 1, 2, 3].firstIndex(of: [0, 1, 2]), 0)
    XCTAssertEqual([0, 1, 2, 3].firstIndex(of: [1, 2]), 1)
    XCTAssertEqual([0, 1, 2, 3].firstIndex(of: [3]), 3)
  }

  func testLogging() {
    let testLogger = Logger(disableOSLog: true, disableNSLog: true)

    var messages: [(String, LogLevel)] = []
    let obj = testLogger.addLogHandler { message, level in
      messages.append((message, level))
    }

    func check(expected: [(String, LogLevel)], file: StaticString = #file, line: UInt = #line) {
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
