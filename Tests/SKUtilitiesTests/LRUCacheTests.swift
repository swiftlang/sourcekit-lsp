//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKTestSupport
import SKUtilities
import XCTest

final class LRUCacheTests: XCTestCase {
  func testGetValue() {
    var lruCache = LRUCache<Int, Int>(capacity: 5)

    // Add key-value pairs up to the cache's capacity
    for i in 1...lruCache.capacity {
      lruCache[i] = i
      XCTAssertEqual(lruCache[i], i)
    }

    // Getting the key-value pair with key 3 should make it MRU
    XCTAssertEqual(lruCache[3], 3)

    // Inserting 4 key-value pairs should keep the MRU key 3
    for i in 6...9 {
      lruCache[i] = i
    }
    assertLRUCacheKeys(lruCache, expectedKeys: [3, 6, 7, 8, 9])
  }

  func testModifyValue() {
    struct ComplexValue: Equatable {
      var real: Int
      var imaginary: Int
    }

    // Add key-value pairs up to the cache's capacity
    var lruCache = LRUCache<Int, ComplexValue>(capacity: 5)
    for i in 1...lruCache.capacity {
      lruCache[i] = ComplexValue(real: i, imaginary: i)
    }

    // Modifying the key-value pair with key 3 should make it MRU
    lruCache[3]?.real = 7

    // Inserting 4 key-value pairs should keep the MRU key 3
    for i in 6...9 {
      lruCache[i] = ComplexValue(real: i, imaginary: i)
    }
    assertLRUCacheKeys(lruCache, expectedKeys: [3, 6, 7, 8, 9])

    // Make sure that the associated value for key 3 has actually been modified
    XCTAssertEqual(lruCache[3], ComplexValue(real: 7, imaginary: 3))
  }

  func testRemoveValue() {
    var lruCache = LRUCache<Int, Int>(capacity: 20)
    for i in 1...10 {
      lruCache[i] = i
    }

    // Remove the key-value pair with key 5
    XCTAssertEqual(lruCache.removeValue(forKey: 5), 5)
    assertLRUCacheKeys(lruCache, expectedKeys: [1, 2, 3, 4, 6, 7, 8, 9, 10])

    // Try to remove a key that does not exist in the cache
    XCTAssertNil(lruCache.removeValue(forKey: 20))
    assertLRUCacheKeys(lruCache, expectedKeys: [1, 2, 3, 4, 6, 7, 8, 9, 10])
  }

  func testRemoveAll() {
    var lruCache = LRUCache<Int, Int>(capacity: 20)
    for i in 1...20 {
      lruCache[i] = i
    }

    // Remove all even keys
    lruCache.removeAll(where: { $0.key % 2 == 0 })
    assertLRUCacheKeys(lruCache, expectedKeys: [1, 3, 5, 7, 9, 11, 13, 15, 17, 19])

    // Remove all key-value pairs
    lruCache.removeAll()
    assertLRUCacheKeys(lruCache, expectedKeys: [])
  }

  func testCaching() {
    var lruCache = LRUCache<Int, Int>(capacity: 5)

    // Insert 5 key-value pairs into the cache
    for i in 1...5 {
      lruCache[i] = i
    }
    assertLRUCacheKeys(lruCache, expectedKeys: [1, 2, 3, 4, 5])

    // Adding a key-value pair should remove the LRU key 1
    lruCache[6] = 6
    assertLRUCacheKeys(lruCache, expectedKeys: [2, 3, 4, 5, 6])

    // Remove 4
    lruCache[4] = nil
    assertLRUCacheKeys(lruCache, expectedKeys: [2, 3, 5, 6])

    // Accessing 2 should move it from LRU to MRU
    XCTAssertEqual(lruCache[2], 2)
    assertLRUCacheKeys(lruCache, expectedKeys: [2, 3, 5, 6])

    // Adding two key-value pairs should remove the LRU key 3
    lruCache[7] = 7
    lruCache[8] = 8
    assertLRUCacheKeys(lruCache, expectedKeys: [2, 5, 6, 7, 8])

    // Assigning to 5 should move it from LRU to MRU
    lruCache[5] = 5
    assertLRUCacheKeys(lruCache, expectedKeys: [2, 5, 6, 7, 8])

    // Adding another value should remove the LRU key 6
    lruCache[9] = 9
    assertLRUCacheKeys(lruCache, expectedKeys: [2, 5, 7, 8, 9])

    // Adding five new key-value pairs should fill the cache
    for i in 21...25 {
      lruCache[i] = i
    }
    assertLRUCacheKeys(lruCache, expectedKeys: [21, 22, 23, 24, 25])

    // Adding five new key-value pairs should fill the cache
    for i in 26...30 {
      lruCache[i] = i
    }
    assertLRUCacheKeys(lruCache, expectedKeys: [26, 27, 28, 29, 30])
  }
}

fileprivate func assertLRUCacheKeys<Key: Comparable, Value>(
  _ lruCache: LRUCache<Key, Value>,
  expectedKeys: [Key],
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(
    Array(lruCache.keys).sorted(),
    expectedKeys.sorted(),
    file: file,
    line: line
  )
}
