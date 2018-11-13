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
@testable import SKSupport
import Basic
import POSIX

final class SupportTests: XCTestCase {

  func testResultEquality() {
    enum MyError: Error, Equatable {
      case err1, err2
    }
    typealias MyResult<T> = Result<T, MyError>

    XCTAssertEqual(MyResult(1), .success(1))
    XCTAssertNotEqual(MyResult(2), .success(1))
    XCTAssertNotEqual(MyResult(.err1), .success(1))
    XCTAssertEqual(MyResult(.err1), MyResult<Int>.failure(.err1))
    XCTAssertNotEqual(MyResult(.err1), MyResult<Int>.failure(.err2))
  }

  func testResultProjection() {
    enum MyError: Error, Equatable {
      case err1, err2
    }
    typealias MyResult<T> = Result<T, MyError>

    XCTAssertEqual(MyResult(1).success, 1)
    XCTAssertNil(MyResult(.err1).success)
    XCTAssertNil(MyResult(1).failure)
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

    let testLogger = Logger()
    Logger.shared = testLogger
    testLogger.disableNSLog = true
    testLogger.disableOSLog = true

    var messages: [(String, LogLevel)] = []
    let obj = testLogger.addLogHandler { message, level in
      messages.append((message, level))
    }

    func check(_ messages: inout [(String, LogLevel)], expected: [(String, LogLevel)], file: StaticString = #file, line: UInt = #line) {
      testLogger.logQueue.sync {}
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

    try! setenv("TEST_ENV_LOGGGING_1", value: "1")
    try! setenv("TEST_ENV_LOGGGING_0", value: "0")
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
    try! setenv("TEST_ENV_LOGGGING_err", value: "")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_err")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ])

    // invalid - no change
    try! setenv("TEST_ENV_LOGGGING_err", value: "a3")
    testLogger.setLogLevel(environmentVariable: "TEST_ENV_LOGGGING_err")

    log("d", level: .error)
    log("e", level: .warning)
    log("f", level: .info)
    log("g", level: .debug)
    check(&messages, expected: [
      ("d", .error),
      ])

    // too high - max out at .debyg
    try! setenv("TEST_ENV_LOGGGING_err", value: "1000")
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
    XCTAssertEqual(table.map { String($0.content) }, expected, file: file, line: line)
  }

  func checkOffsets(_ string: String, _ expected: [Int], file: StaticString = #file, line: UInt = #line) {
    let table = LineTable(string)
    XCTAssertEqual(table.map { $0.utf8Offset }, expected, file: file, line: line)
  }

  func testLineTable() {
    checkLines("", [""])
    checkLines("a", ["a"])
    checkLines("abc", ["abc"])
    checkLines("abc\n", ["abc\n", ""])
    checkLines("\n", ["\n", ""])
    checkLines("\n\n", ["\n", "\n", ""])
    checkLines("\r\n", ["\r\n", ""])
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

    XCTAssertEqual(LineTable("")[0].content, "")
    XCTAssertEqual(LineTable("\n")[1].content, "")

    XCTAssertEqual(LineTable("")[utf8Offset: 0].index, 0)
    XCTAssertEqual(LineTable("\n")[utf8Offset: 0].index, 0)
    XCTAssertEqual(LineTable("\n")[utf8Offset: 1].index, 1)
    XCTAssertEqual(LineTable("\n")[utf8Offset: 199].index, 1)
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

  func testLineTableAppendPerf() {

    let characters: [Character] = [
      "\t", "\n"
    ] + (32...126).map { Character(UnicodeScalar($0)) }

    // The debug performance is shockingly bad.
    #if DEBUG
    let iterations = 1_000
    #else
    let iterations = 10_000
    #endif

    self.measure {
      var lcg = SimpleLCG(seed: 1)
      var t = LineTable("")
      var line = 0
      var col = 0
      for _ in 1...iterations {
        let c = characters.randomElement(using: &lcg)!
        t.replace(fromLine: line, utf16Offset: col, toLine: line, utf16Offset: col, with: String(c))
        col += 1
        if c == "\n" {
          line += 1
          col = 0
        }
      }
    }
  }

  func testLineTableSingleCharEditPerf() {

    let characters: [Character] = [
      "\t", "\n"
      ] + (32...126).map { Character(UnicodeScalar($0)) }

    // The debug performance is shockingly bad.
    #if DEBUG
    let iterations = 1_000
    let size = 1_000
    #else
    let iterations = 10_000
    let size = 10_000
    #endif

    self.measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
      var lcg = SimpleLCG(seed: 1)
      var str = ""
      for _ in 1...size {
        str += String(characters.randomElement(using: &lcg)!)
      }

      var t = LineTable(str)

      self.startMeasuring()

      for _ in 1...iterations {
        let line = (0..<(t.count-1)).randomElement()!
        let col = (0 ..< (t[line+1].utf16Offset - t[line].utf16Offset)).randomElement()!
        let len = Bool.random() ? 1 : 0
        var newText = String(characters.randomElement(using: &lcg)!)
        if len == 1 && Bool.random() {
          newText = "" // deletion
        }

        t.replace(fromLine: line, utf16Offset: col, utf16Length: len, with: newText)
      }

      self.stopMeasuring()
    }
  }

  static var allTests = [
    ("testResultEquality", testResultEquality),
    ("testResultProjection", testResultProjection),
    ("testIntFromAscii", testIntFromAscii),
    ("testFindSubsequence", testFindSubsequence),
    ("testLogging", testLogging),
    ]
}
