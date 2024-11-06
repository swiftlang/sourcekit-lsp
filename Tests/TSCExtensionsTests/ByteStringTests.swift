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

import TSCExtensions
import XCTest

// import SKSupport
// import SwiftExtensions
import struct TSCBasic.ByteString

final class ByteStringTests: XCTestCase {
  func testByteStringWithUnsafeData() {
    ByteString(encodingAsUTF8: "").withUnsafeData { data in
      XCTAssertEqual(data.count, 0)
    }
    ByteString(encodingAsUTF8: "abc").withUnsafeData { data in
      XCTAssertEqual(data.count, 3)
    }
  }

}
