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

import SwiftExtensions
import XCTest

final class ResultExtensionsTests: XCTestCase {
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
}
