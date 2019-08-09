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

import XCTest
import SKSupport
import Basic

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
    let orig = Logger.shared
    defer { Logger.shared = orig }

    let testLogger = Logger(disableOSLog: true, disableNSLog: true)
    Logger.shared = testLogger

    var messages: [(String, LogLevel)] = []
    let obj = testLogger.addLogHandler { message, level in
      messages.append((message, level))
    }

    func check(_ messages: inout [(String, LogLevel)], expected: [(String, LogLevel)], file: StaticString = #file, line: UInt = #line) {
      testLogger.flush()
      XCTAssert(messages == expected, "\(messages) does not match expected \(expected)", file: file, line: line)
      messages.removeAll()
    }

    testLogger.currentLevel = .default

    log("a")
    check(&messages, expected: [("a", .default)])
    check(&messages, expected: [])

    log("b\n\nc")
    check(&messages, expected: [("b\n\nc", .default)])

    enum MyError: Error { case one }
    func throw1(_ x: Int) throws -> Int {
      if x == 1 { throw MyError.one }
      return x
    }

    XCTAssertEqual(orLog { try throw1(0) }, 0)
    check(&messages, expected: [])
    XCTAssertNil(orLog { try throw1(1) })
    check(&messages, expected: [("one", .default)])
    XCTAssertNil(orLog("hi") { try throw1(1) })
    check(&messages, expected: [("hi one", .default)])

    logAsync { (currentLevel) -> String? in
      return "\(currentLevel)"
    }
    check(&messages, expected: [("info", .default)])

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ("e", .warning),
      ("f", .info),
      ])

    testLogger.currentLevel = .warning

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ("e", .warning),
      ])

    testLogger.currentLevel = .error

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ])

    testLogger.currentLevel = .default

    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_1", value: "1")
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_0", value: "0")
    // .warning
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_1")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ("e", .warning),
      ])

    // .error
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_0")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ])

    // missing - no change
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_err")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ])

    // invalid - no change
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_err", value: "")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_err")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ])

    // invalid - no change
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_err", value: "a3")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_err")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ])

    // too high - max out at .debug
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_err", value: "1000")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_err")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ("e", .warning),
      ("f", .info),
      ("g", .debug),
      ])

    // By string.
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_string", value: "error")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_string")
    XCTAssertEqual(testLogger.currentLevel, .error)
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_string", value: "warning")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_string")
    XCTAssertEqual(testLogger.currentLevel, .warning)
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_string", value: "info")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_string")
    XCTAssertEqual(testLogger.currentLevel, .info)
    try! ProcessEnv.setVar("TEST_ENV_LOGGGING_string", value: "debug")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_string")
    XCTAssertEqual(testLogger.currentLevel, .debug)

    testLogger.currentLevel = .default
    testLogger.addLogHandler(obj)

    log("a")
    check(&messages, expected: [
      ("a", .default),
      ("a", .default),
      ])

    testLogger.removeLogHandler(obj)

    log("a")
    check(&messages, expected: [])
  }

  func checkLines(_ string: String, _ expected: [String], file: StaticString = #file, line: UInt = #line) {
    let table = LineTable(string)
    XCTAssertEqual(table.map { String($0) }, expected, file: file, line: line)
  }

  func checkOffsets(_ string: String, _ expected: [Int], file: StaticString = #file, line: UInt = #line) {
    let table = LineTable(string)
    XCTAssertEqual(table.map { string.utf8.distance(from: string.startIndex, to: $0.startIndex) }, expected, file: file, line: line)
  }

  func testLineTable() {
    checkLines("", [""])
    checkLines("a", ["a"])
    checkLines("abc", ["abc"])
    checkLines("abc\n", ["abc\n", ""])
    checkLines("\n", ["\n", ""])
    checkLines("\n\n", ["\n", "\n", ""])
    checkLines("\r\n", ["\r\n", ""])
    checkLines("\r\r", ["\r", "\r", ""])
    checkLines("a\nb", ["a\n", "b"])
    checkLines("a\nb\n", ["a\n", "b\n", ""])
    checkLines("a\nb\nccccc", ["a\n", "b\n", "ccccc"])

    checkLines("\u{1}\nb", ["\u{1}\n", "b"])
    checkLines("\u{10000}\nb", ["\u{10000}\n", "b"])
    checkLines("\n\u{10000}", ["\n", "\u{10000}"])
    checkLines("\n\u{10000}b", ["\n", "\u{10000}b"])
    checkLines("\n\u{10000}\nc", ["\n", "\u{10000}\n", "c"])
    checkLines("\n\u{10000}b\nc", ["\n", "\u{10000}b\n", "c"])

    checkOffsets("a", [0])
    checkOffsets("abc", [0])
    checkOffsets("\n", [0, 1])
    checkOffsets("\n\n", [0, 1, 2])
    checkOffsets("\n\r\n\n", [0, 1, 3, 4])
    checkOffsets("a\nb", [0, 2])
    checkOffsets("a\nb\n", [0, 2, 4])
    checkOffsets("a\nbbb\nccccc", [0, 2, 6])
    checkOffsets("a\nbbb\nccccc", [0, 2, 6])

    checkOffsets("\u{1}\nb", [0, 2])
    checkOffsets("\u{100}\nb", [0, 3])
    checkOffsets("\u{1000}\nb", [0, 4])
    checkOffsets("\u{10000}\nb", [0, 5])
    checkOffsets("\n\u{10000}", [0, 1])
    checkOffsets("\n\u{10000}b", [0, 1])
    checkOffsets("\n\u{10000}b\nc", [0, 1, 7])

    XCTAssertEqual(LineTable("")[0], "")
    XCTAssertEqual(LineTable("\n")[1], "")
  }

  func checkLineAndColumns(_ table: LineTable, _ utf8Offset: Int, _ expected: (line: Int, utf16Column: Int)?, file: StaticString = #file, line: UInt = #line) {
    switch (table.lineAndUTF16ColumnOf(utf8Offset: utf8Offset), expected) {
    case (nil, nil):
      break
    case (let result?, let _expected?):
      XCTAssertTrue(result == _expected, "\(result) != \(_expected)", file: file, line: line)
    case (let result, let _expected):
      XCTFail("\(String(describing: result)) != \(String(describing: _expected))", file: file, line: line)
    }
  }

  func checkUTF8OffsetOf(_ table: LineTable, _ query: (line: Int, utf16Column: Int), _ expected: Int?, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(table.utf8OffsetOf(line: query.line, utf16Column: query.utf16Column), expected, file: file, line: line)
  }

  func checkUTF16ColumnAt(_ table: LineTable, _ query: (line: Int, utf8Column: Int), _ expected: Int?, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(table.utf16ColumnAt(line: query.line, utf8Column: query.utf8Column), expected, file: file, line: line)
  }

  func testLineTableLinePositionTranslation() {
    let t1 = LineTable("""
      0123
      5678
      abcd
      """)
    checkLineAndColumns(t1, 0, (line: 0, utf16Column: 0))
    checkLineAndColumns(t1, 2, (line: 0, utf16Column: 2))
    checkLineAndColumns(t1, 4, (line: 0, utf16Column: 4))
    checkLineAndColumns(t1, 5, (line: 1, utf16Column: 0))
    checkLineAndColumns(t1, 9, (line: 1, utf16Column: 4))
    checkLineAndColumns(t1, 10, (line: 2, utf16Column: 0))
    checkLineAndColumns(t1, 14, (line: 2, utf16Column: 4))
    checkLineAndColumns(t1, 15, nil)

    checkUTF8OffsetOf(t1, (line: 0, utf16Column: 0), 0)
    checkUTF8OffsetOf(t1, (line: 0, utf16Column: 2), 2)
    checkUTF8OffsetOf(t1, (line: 0, utf16Column: 4), 4)
    checkUTF8OffsetOf(t1, (line: 0, utf16Column: 5), 5)
    checkUTF8OffsetOf(t1, (line: 0, utf16Column: 6), nil)
    checkUTF8OffsetOf(t1, (line: 1, utf16Column: 0), 5)
    checkUTF8OffsetOf(t1, (line: 1, utf16Column: 4), 9)
    checkUTF8OffsetOf(t1, (line: 2, utf16Column: 0), 10)
    checkUTF8OffsetOf(t1, (line: 2, utf16Column: 4), 14)
    checkUTF8OffsetOf(t1, (line: 2, utf16Column: 5), nil)
    checkUTF8OffsetOf(t1, (line: 3, utf16Column: 0), nil)

    checkUTF16ColumnAt(t1, (line: 0, utf8Column: 4), 4)
    checkUTF16ColumnAt(t1, (line: 0, utf8Column: 5), 5)
    checkUTF16ColumnAt(t1, (line: 0, utf8Column: 6), nil)
    checkUTF16ColumnAt(t1, (line: 2, utf8Column: 0), 0)
    checkUTF16ColumnAt(t1, (line: 3, utf8Column: 0), nil)

    let t2 = LineTable("""
      こんにちは
      안녕하세요
      \u{1F600}\u{1F648}
      """)
    checkLineAndColumns(t2, 0, (line: 0, utf16Column: 0))
    checkLineAndColumns(t2, 15, (line: 0, utf16Column: 5))
    checkLineAndColumns(t2, 19, (line: 1, utf16Column: 1))
    checkLineAndColumns(t2, 32, (line: 2, utf16Column: 0))
    checkLineAndColumns(t2, 36, (line: 2, utf16Column: 2))
    checkLineAndColumns(t2, 40, (line: 2, utf16Column: 4))

    checkUTF8OffsetOf(t2, (line: 0, utf16Column: 0), 0)
    checkUTF8OffsetOf(t2, (line: 0, utf16Column: 5), 15)
    checkUTF8OffsetOf(t2, (line: 0, utf16Column: 6), 16)
    checkUTF8OffsetOf(t2, (line: 1, utf16Column: 1), 19)
    checkUTF8OffsetOf(t2, (line: 1, utf16Column: 6), 32)
    checkUTF8OffsetOf(t2, (line: 1, utf16Column: 7), nil)
    checkUTF8OffsetOf(t2, (line: 2, utf16Column: 0), 32)
    checkUTF8OffsetOf(t2, (line: 2, utf16Column: 2), 36)
    checkUTF8OffsetOf(t2, (line: 2, utf16Column: 4), 40)
    checkUTF8OffsetOf(t2, (line: 2, utf16Column: 5), nil)

    checkUTF16ColumnAt(t2, (line: 0, utf8Column: 3), 1)
    checkUTF16ColumnAt(t2, (line: 0, utf8Column: 15), 5)
    checkUTF16ColumnAt(t2, (line: 2, utf8Column: 4), 2)
  }

  func testLineTableEditing() {
    var t = LineTable("")
    t.replace(fromLine: 0, utf16Offset: 0, utf16Length: 0, with: "a")
    XCTAssertEqual(t, LineTable("a"))
    t.replace(fromLine: 0, utf16Offset: 0, utf16Length: 0, with: "cb")
    XCTAssertEqual(t, LineTable("cba"))
    t.replace(fromLine: 0, utf16Offset: 1, utf16Length: 1, with: "d")
    XCTAssertEqual(t, LineTable("cda"))
    t.replace(fromLine: 0, utf16Offset: 3, utf16Length: 0, with: "e")
    XCTAssertEqual(t, LineTable("cdae"))
    t.replace(fromLine: 0, utf16Offset: 3, utf16Length: 1, with: "")
    XCTAssertEqual(t, LineTable("cda"))

    t = LineTable("a")
    t.replace(fromLine: 0, utf16Offset: 0, utf16Length: 0, with: "\n")
    XCTAssertEqual(t, LineTable("\na"))
    t.replace(fromLine: 1, utf16Offset: 0, utf16Length: 0, with: "\n")
    XCTAssertEqual(t, LineTable("\n\na"))
    t.replace(fromLine: 2, utf16Offset: 1, utf16Length: 0, with: "\n")
    XCTAssertEqual(t, LineTable("\n\na\n"))

    t = LineTable("""
    abcd
    efgh
    """)

    t.replace(fromLine: 0, utf16Offset: 2, toLine: 1, utf16Offset: 1, with: "x")
    XCTAssertEqual(t, LineTable("abxfgh"))

    t.replace(fromLine: 0, utf16Offset: 2, toLine: 0, utf16Offset: 4, with: "p\nq\n")
    XCTAssertEqual(t, LineTable("abp\nq\ngh"))
  }

  func testByteStringWithUnsafeData() {
    ByteString(encodingAsUTF8: "").withUnsafeData { data in
      XCTAssertEqual(data.count, 0)
    }
    ByteString(encodingAsUTF8: "abc").withUnsafeData { data in
      XCTAssertEqual(data.count, 3)
    }
  }

  func testExpandingTilde() {
    XCTAssertEqual(AbsolutePath(expandingTilde: "~/foo").basename, "foo")
    XCTAssertNotEqual(AbsolutePath(expandingTilde: "~/foo").parentDirectory, .root)
    XCTAssertEqual(AbsolutePath(expandingTilde: "/foo"), AbsolutePath("/foo"))
  }
}
