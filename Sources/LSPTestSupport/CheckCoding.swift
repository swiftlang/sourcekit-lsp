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

import Foundation
import XCTest

/// Checks the encoding of the given value against the given json string and verifies that decoding the json reproduces the original value (according to its equatable conformance).
///
/// - parameter value: The value to encode/decode.
/// - parameter json: The expected json encoding.
public func checkCoding<T>(_ value: T, json: String, file: StaticString = #filePath, line: UInt = #line) where T: Codable & Equatable {
  let encoder = JSONEncoder()
  encoder.outputFormatting.insert(.prettyPrinted)
  if #available(macOS 10.13, *) {
   encoder.outputFormatting.insert(.sortedKeys)
  }
  let data = try! encoder.encode(WrapFragment(value: value))
  let wrappedStr = String(data: data, encoding: .utf8)!

  /// Strip off WrapFragment encoding `{"value":}` and extra indentation.
  let pre = "{\n  \"value\" : "
  let suff = "\n}"
  XCTAssert(wrappedStr.hasPrefix(pre))
  XCTAssert(wrappedStr.hasSuffix(suff))
  let str = String(wrappedStr.dropFirst(pre.count).dropLast(suff.count))
    // Remove extra indentation
    .replacingOccurrences(of: "\n  ", with: "\n")
    // Remove trailing whitespace to normalize between corelibs and Apple Foundation.
    .trimmingTrailingWhitespace()

  // Requires sortedKeys. Silently drop the check if it's not available.
  if #available(macOS 10.13, *) {
    XCTAssertEqual(json, str, file: file, line: line)
  }

  let decoder = JSONDecoder()
  let decodedValue = try! decoder.decode(WrapFragment<T>.self, from: data).value

  XCTAssertEqual(value, decodedValue, file: file, line: line)
}

/// JSONEncoder requires the top-level value to be encoded as a JSON container (array or object). Give it one.
private struct WrapFragment<T>: Equatable, Codable where T: Equatable & Codable {
  var value: T
}

/// Checks that decoding the given string is equal to the expected value.
///
/// - parameter value: The value to encode/decode.
/// - parameter json: The expected json encoding.
public func checkDecoding<T>(json: String, expected value: T, file: StaticString = #filePath, line: UInt = #line) where T: Codable & Equatable {

  let wrappedStr = "{\"value\":\(json)}"
  let data = wrappedStr.data(using: .utf8)!
  let decoder = JSONDecoder()
  let decodedValue = try! decoder.decode(WrapFragment<T>.self, from: data).value

  XCTAssertEqual(value, decodedValue, file: file, line: line)
}

public func checkCoding<T>(_ value: T, json: String, userInfo: [CodingUserInfoKey: Any] = [:], file: StaticString = #filePath, line: UInt = #line, body: (T) -> Void) where T: Codable {
  let encoder = JSONEncoder()
  encoder.outputFormatting.insert(.prettyPrinted)
  if #available(macOS 10.13, *) {
   encoder.outputFormatting.insert(.sortedKeys)
  }
  let data = try! encoder.encode(value)
  let str = String(data: data, encoding: .utf8)!
    // Remove trailing whitespace to normalize between corelibs and Apple Foundation.
    .trimmingTrailingWhitespace()

  // Requires sortedKeys. Silently drop the check if it's not available.
  if #available(macOS 10.13, *) {
    XCTAssertEqual(json, str, file: file, line: line)
  }

  let decoder = JSONDecoder()
  decoder.userInfo = userInfo
  let decodedValue = try! decoder.decode(T.self, from: data)

  body(decodedValue)
}

extension String {
  // This is fileprivate because the implementation is really slow; to use it outside a test it should be optimized.
  fileprivate func trimmingTrailingWhitespace() -> String {
    return self.replacingOccurrences(of: "[ ]+\\n", with: "\n", options: .regularExpression)
  }
}
