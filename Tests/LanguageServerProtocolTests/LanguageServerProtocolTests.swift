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

@testable import LanguageServerProtocol

import XCTest

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
}
