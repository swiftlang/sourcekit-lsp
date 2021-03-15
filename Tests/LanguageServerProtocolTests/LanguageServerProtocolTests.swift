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

import XCTest

fileprivate func AssertDataIsString(
  _ data: Data,
  expected: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let got = String(decoding: data, as: UTF8.self)
  XCTAssertEqual(got, expected, "data not equal to string", file: file, line: line)
}

final class LanguageServerProtocolTests: XCTestCase {

  func testLanguageXFlag() {
    XCTAssertEqual(Language.c.xflag, "c")
    XCTAssertEqual(Language.c.xflagHeader, "c-header")
    XCTAssertEqual(Language.cpp.xflag, "c++")
    XCTAssertEqual(Language.cpp.xflagHeader, "c++-header")
    XCTAssertEqual(Language.objective_c.xflag, "objective-c")
    XCTAssertEqual(Language.objective_c.xflagHeader, "objective-c-header")
    XCTAssertEqual(Language.objective_cpp.xflag, "objective-c++")
    XCTAssertEqual(Language.objective_cpp.xflagHeader, "objective-c++-header")
  }

  func testURLEscaping() {
    let fileURI = DocumentURI(URL(fileURLWithPath: "/folder/image@3x.png", isDirectory: false))
    let encodedURI = DocumentURI(string: "file:///folder/image%403x.png")
    XCTAssertEqual(encodedURI, fileURI)
    XCTAssertEqual(encodedURI.hashValue, fileURI.hashValue)
  }

  func testFileChangeTypeEncoding() throws {
    let encoder = JSONEncoder()
    try AssertDataIsString(encoder.encode(FileChangeType.created), expected: "1")
    try AssertDataIsString(encoder.encode(FileChangeType.changed), expected: "2")
    try AssertDataIsString(encoder.encode(FileChangeType.deleted), expected: "3")
    try AssertDataIsString(encoder.encode(FileChangeType(rawValue: 5)), expected: "5")
  }
}
