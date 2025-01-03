//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring
import XCTest

class StackAllocateTests: XCTestCase {
  func testAllocating() throws {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      let sum3: Int = allocator.withStackArray(of: Int.self, maximumCapacity: 3) { buffer in
        buffer.append(2)
        buffer.append(4)
        buffer.append(6)
        return buffer.sum()
      }
      XCTAssertEqual(sum3, 12)
      let sum10240: Int = allocator.withStackArray(of: Int.self, maximumCapacity: 10240) { buffer in
        buffer.fill(with: 33)
        return buffer.sum()
      }
      XCTAssertEqual(sum10240, 10240 * 33)

      allocator.withStackArray(of: Int.self, maximumCapacity: 3) { buffer in
        XCTAssertEqual(buffer.first, nil)
        XCTAssertEqual(buffer.last, nil)
        XCTAssertEqual(buffer.sum(), 0)
        buffer.append(2)
        XCTAssertEqual(buffer.first, 2)
        XCTAssertEqual(buffer.last, 2)
        XCTAssertEqual(buffer.sum(), 2)
        buffer.removeLast()
        XCTAssertEqual(buffer.first, nil)
        XCTAssertEqual(buffer.last, nil)
        XCTAssertEqual(buffer.sum(), 0)
      }
    }
  }

  func testPopLast() throws {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      allocator.withStackArray(of: Int.self, maximumCapacity: 1) { buffer in
        XCTAssertEqual(nil, buffer.popLast())
        buffer.append(1)
        XCTAssertEqual(1, buffer.popLast())
        XCTAssertEqual(0, buffer.count)
        XCTAssertEqual(nil, buffer.popLast())
      }
    }
  }

  func testTruncateTo() throws {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      allocator.withStackArray(of: Int.self, maximumCapacity: 2) { buffer in
        XCTAssertEqual(buffer.count, 0)
        buffer.truncate(to: 0)
        XCTAssertEqual(buffer.count, 0)
        buffer.truncate(to: 1)
        XCTAssertEqual(buffer.count, 0)

        buffer.append(0)
        buffer.truncate(to: 1)
        XCTAssertEqual(Array(buffer), [0])
        buffer.truncate(to: 0)
        XCTAssertEqual(Array(buffer), [])

        buffer.append(0)
        buffer.append(1)
        buffer.truncate(to: 2)
        XCTAssertEqual(Array(buffer), [0, 1])
        buffer.truncate(to: 1)
        XCTAssertEqual(Array(buffer), [0])
        buffer.append(1)
        buffer.truncate(to: 0)
        XCTAssertEqual(Array(buffer), [])
      }
    }
  }

  func testRemoveAll() throws {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      allocator.withStackArray(of: Int.self, maximumCapacity: 2) { buffer in
        XCTAssertEqual(buffer.count, 0)
        buffer.removeAll()
        XCTAssertEqual(buffer.count, 0)
        buffer.append(0)
        XCTAssertEqual(buffer.count, 1)
        buffer.removeAll()
        XCTAssertEqual(buffer.count, 0)
        buffer.append(0)
        buffer.append(0)
        XCTAssertEqual(buffer.count, 2)
        buffer.removeAll()
        XCTAssertEqual(buffer.count, 0)
      }
    }
  }
}
