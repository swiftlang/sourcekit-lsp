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

import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import XCTest

final class MessageParsingTests: XCTestCase {

  func testSplitMessage() {
    func check(_ string: String, contentLen: Int? = nil, restLen: Int?, file: StaticString = #filePath, line: UInt = #line) {
      let bytes: [UInt8] = [UInt8](string.utf8)
      guard let ((content, header), rest) = try! bytes.jsonrpcSplitMessage() else {
        XCTAssert(restLen == nil, "expected non-empty field", file: file, line: line)
        return
      }
      XCTAssertEqual(rest.count, restLen, "rest", file: file, line: line)
      XCTAssertEqual(content.count, contentLen, "content", file: file, line: line)
      XCTAssertEqual(header.contentLength, contentLen, file: file, line: line)
    }

    func checkError(_ string: String, _ expected: MessageDecodingError, file: StaticString = #filePath, line: UInt = #line) {
      do {
        _ = try [UInt8](string.utf8).jsonrpcSplitMessage()
        XCTFail("missing expected error", file: file, line: line)
      } catch let error as MessageDecodingError {
        XCTAssertEqual(error, expected, file: file, line: line)
      } catch {
        XCTFail("error \(error) does not match expected \(expected)", file: file, line: line)
      }
    }

    check("Content-Length: 2\r\n", restLen: nil)
    check("Content-Length: 1\r\n\r\n", restLen: nil)
    check("Content-Length: 2\r\n\r\n{", restLen: nil)

    check("Content-Length: 0\r\n\r\n", contentLen: 0,  restLen: 0)
    check("Content-Length: 0\r\n\r\n{}", contentLen: 0,  restLen: 2)
    check("Content-Length: 1\r\n\r\n{}", contentLen: 1,  restLen: 1)
    check("Content-Length: 2\r\n\r\n{}", contentLen: 2,  restLen: 0)
    check("Content-Length: 2\r\n\r\n{}Co", contentLen: 2,  restLen: 2)

    checkError("\r\n\r\n{}", MessageDecodingError.parseError("missing Content-Length header"))
  }

  func testParseHeader() {
    func check(_ string: String, header expected: JSONRPCMessageHeader? = nil, restLen: Int?, file: StaticString = #filePath, line: UInt = #line) {
      let bytes: [UInt8] = [UInt8](string.utf8)
      guard let (header, rest) = try! bytes.jsonrcpParseHeader() else {
        XCTAssert(restLen == nil, "expected non-empty field", file: file, line: line)
        return
      }
      XCTAssertEqual(rest.count, restLen, "rest", file: file, line: line)
      XCTAssertEqual(header, expected, file: file, line: line)
    }

    func checkErrorBytes(_ bytes: [UInt8], _ expected: MessageDecodingError, file: StaticString = #filePath, line: UInt = #line) {
      do {
        _ = try bytes.jsonrcpParseHeader()
        XCTFail("missing expected error", file: file, line: line)
      } catch let error as MessageDecodingError {
        XCTAssertEqual(error, expected, file: file, line: line)
      } catch {
        XCTFail("error \(error) does not match expected \(expected)", file: file, line: line)
      }
    }

    func checkError(_ string: String, _ expected: MessageDecodingError, file: StaticString = #filePath, line: UInt = #line) {
      checkErrorBytes([UInt8](string.utf8), expected, file: file, line: line)
    }

    check("", restLen: nil)
    check("C", restLen: nil)
    check("Content-Length: 1", restLen: nil)
    check("Content-Length: 1\r", restLen: nil)
    check("Content-Length: 1\r\n", restLen: nil)
    check("Content-Length: 1\r\n\r\n", header: JSONRPCMessageHeader(contentLength: 1), restLen: 0)
    check("Content-Length: 1\r\n\r\n{}", header: JSONRPCMessageHeader(contentLength: 1), restLen: 2)
    check("A:B\r\nContent-Length: 1\r\nC:D\r\n\r\n", header: JSONRPCMessageHeader(contentLength: 1), restLen: 0)
    check("Content-Length:123   \r\n\r\n", header: JSONRPCMessageHeader(contentLength: 123), restLen: 0)

    checkError("Content-Length:0x1\r\n\r\n", MessageDecodingError.parseError("expected integer value in 0x1"))
    checkError("Content-Length:a123\r\n\r\n", MessageDecodingError.parseError("expected integer value in a123"))

    checkErrorBytes([UInt8]("Content-Length: ".utf8) + [0xFF] + [UInt8]("\r\n".utf8), MessageDecodingError.parseError("expected integer value in <invalid>"))
  }

  func testParseHeaderField() {
    func check(_ string: String, keyLen: Int? = nil, valueLen: Int? = nil, restLen: Int?, file: StaticString = #filePath, line: UInt = #line) {
      let bytes: [UInt8] = [UInt8](string.utf8)
      guard let (kv, rest) = try! bytes.jsonrpcParseHeaderField() else {
        XCTAssert(restLen == nil, "expected non-empty field", file: file, line: line)
        return
      }
      XCTAssertEqual(rest.count, restLen, "rest", file: file, line: line)
      XCTAssertEqual(kv?.key.count, keyLen, "key", file: file, line: line)
      if let key = kv?.key {
        XCTAssertEqual(key, bytes.prefix(key.count), file: file, line: line)
      }
      XCTAssertEqual(kv?.value.count, valueLen, "value", file: file, line: line)
      if let value = kv?.value {
        XCTAssertEqual(value, bytes.dropFirst(kv!.key.count+1).prefix(value.count), file: file, line: line)
      }
    }

    func checkError(_ string: String, _ expected: MessageDecodingError, file: StaticString = #filePath, line: UInt = #line) {
      do {
        _ = try [UInt8](string.utf8).jsonrpcParseHeaderField()
        XCTFail("missing expected error", file: file, line: line)
      } catch let error as MessageDecodingError {
        XCTAssertEqual(error, expected, file: file, line: line)
      } catch {
        XCTFail("error \(error) does not match expected \(expected)", file: file, line: line)
      }
    }

    check("", restLen: nil)
    check("C", restLen: nil)
    check("Content-Length", restLen: nil)
    check("Content-Length:", restLen: nil)
    check("Content-Length:a", restLen: nil)
    check("Content-Length: 1", restLen: nil)
    check("Content-Length: 1\r", restLen: nil)
    check("Content-Length: 1\r\n", keyLen: "Content-Length".count, valueLen: 2, restLen: 0)
    check("Content-Length:1\r\n", keyLen: "Content-Length".count, valueLen: 1, restLen: 0)
    check("Content-Length: 1\r\n ", keyLen: "Content-Length".count, valueLen: 2, restLen: 1)
    check("Content-Length: 1\r\n\r\n", keyLen: "Content-Length".count, valueLen: 2, restLen: 2)
    check("Unknown:asdf\r", restLen: nil)
    check("Unknown:asdf\r\n", keyLen: "Unknown".count, valueLen: 4, restLen: 0)
    check("\r", restLen: nil)
    check("\r\n", restLen: 0)
    check("\r\nC", restLen: 1)
    check("\r\nContent-Length:1\r\n", restLen: "Content-Length:1\r\n".utf8.count)
    check(":", restLen: nil)
    check(":\r\n", keyLen: 0, valueLen: 0, restLen: 0)

    checkError("C\r\n", MessageDecodingError.parseError("expected ':' in message header"))
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

    XCTAssertEqual(Int(ascii: "1234567890"), 1234567890)
    XCTAssertEqual(Int(ascii: "\n\r \u{b}\u{d}\t45\n\t\r\u{c}"), 45)
  }
}
