//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

private struct Bytes8 { var storage: (UInt64) = (0) }
private struct Bytes16 { var storage: (Bytes8, Bytes8) = (.init(), .init()) }
private struct Bytes32 { var storage: (Bytes16, Bytes16) = (.init(), .init()) }
private struct Bytes64 { var storage: (Bytes32, Bytes32) = (.init(), .init()) }
private struct Bytes128 { var storage: (Bytes64, Bytes64) = (.init(), .init()) }
private struct Bytes256 { var storage: (Bytes128, Bytes128) = (.init(), .init()) }
private struct Bytes512 { var storage: (Bytes256, Bytes256) = (.init(), .init()) }
private struct Bytes1024 { var storage: (Bytes512, Bytes512) = (.init(), .init()) }
private struct Bytes2048 { var storage: (Bytes1024, Bytes1024) = (.init(), .init()) }
private struct Bytes4096 { var storage: (Bytes2048, Bytes2048) = (.init(), .init()) }
private struct Bytes8192 { var storage: (Bytes4096, Bytes4096) = (.init(), .init()) }

package struct UnsafeStackAllocator {
  private typealias Storage = Bytes8192
  private var storage = Storage()
  private static let pageSize = 64
  private static let storageCapacity = MemoryLayout<Storage>.size
  private var pagesAllocated = 0
  private var pagesAvailable: Int {
    pagesCapacity - pagesAllocated
  }

  private init() {
  }

  package static func withUnsafeStackAllocator<R>(body: (inout Self) throws -> R) rethrows -> R {
    var allocator = Self()
    defer { assert(allocator.pagesAllocated == 0) }
    return try body(&allocator)
  }

  private let pagesCapacity = Self.storageCapacity / Self.pageSize

  private func pages<Element>(for type: Element.Type, maximumCapacity: Int) -> Int {
    let bytesNeeded = MemoryLayout<Element>.stride * maximumCapacity
    return ((bytesNeeded - 1) / Self.pageSize) + 1
  }

  private mutating func allocate<Element>(
    of type: Element.Type,
    maximumCapacity: Int
  ) -> UnsafeMutablePointer<Element> {
    // Avoid dealing with alignment for now.
    assert(MemoryLayout<Element>.alignment <= MemoryLayout<Storage>.alignment)
    // Avoid dealing with alignment for now.
    assert(MemoryLayout<Element>.alignment <= Self.pageSize)
    let pagesNeeded = pages(for: type, maximumCapacity: maximumCapacity)
    if pagesNeeded < pagesAvailable {
      return withUnsafeMutableBytes(of: &storage) { arena in
        let start = arena.baseAddress!.advanced(by: pagesAllocated * Self.pageSize).bindMemory(
          to: Element.self,
          capacity: maximumCapacity
        )
        pagesAllocated += pagesNeeded
        return start
      }
    } else {
      return UnsafeMutablePointer<Element>.allocate(capacity: maximumCapacity)
    }
  }

  mutating func allocateBuffer<Element>(of type: Element.Type, count: Int) -> UnsafeMutableBufferPointer<Element> {
    return UnsafeMutableBufferPointer(start: allocate(of: type, maximumCapacity: count), count: count)
  }

  mutating func allocateUnsafeArray<Element>(
    of type: Element.Type,
    maximumCapacity: Int
  ) -> UnsafeStackArray<Element> {
    UnsafeStackArray(base: allocate(of: type, maximumCapacity: maximumCapacity), capacity: maximumCapacity)
  }

  mutating private func deallocate<Element>(_ base: UnsafePointer<Element>, capacity: Int) {
    let arrayStart = UnsafeRawPointer(base)
    let arrayPages = pages(for: Element.self, maximumCapacity: capacity)
    withUnsafeBytes(of: &storage) { arena in
      let arenaStart = UnsafeRawPointer(arena.baseAddress)!
      let arenaEnd = arenaStart.advanced(by: Self.storageCapacity)
      if (arrayStart >= arenaStart) && (arrayStart < arenaEnd) {
        let projectedArrayStart = arenaStart.advanced(by: (pagesAllocated - arrayPages) * Self.pageSize)
        assert(projectedArrayStart == arrayStart, "deallocate(...) must be called in FIFO order.")
        pagesAllocated -= arrayPages
      } else {
        arrayStart.deallocate()
      }
    }
  }

  /// - Note: `buffer.count` must the be the same as from the original allocation.
  /// - Note: deiniting buffer contents is caller's responsibility.
  mutating func deallocate<Element>(_ buffer: inout UnsafeBufferPointer<Element>) {
    if let baseAddress = buffer.baseAddress {
      deallocate(baseAddress, capacity: buffer.count)
      buffer = UnsafeBufferPointer(start: nil, count: 0)
    }
  }

  /// - Note: `buffer.count` must the be the same as from the original allocation.
  /// - Note: deiniting buffer contents is caller's responsibility.
  mutating func deallocate<Element>(_ buffer: inout UnsafeMutableBufferPointer<Element>) {
    if let baseAddress = buffer.baseAddress {
      deallocate(baseAddress, capacity: buffer.count)
      buffer = UnsafeMutableBufferPointer(start: nil, count: 0)
    }
  }

  mutating func deallocate<Element>(_ array: inout UnsafeStackArray<Element>) {
    array.prepareToDeallocate()
    deallocate(array.base, capacity: array.capacity)
    array = UnsafeStackArray(base: array.base, capacity: 0)
  }

  package mutating func withStackArray<Element, R>(
    of elementType: Element.Type,
    maximumCapacity: Int,
    body: (inout UnsafeStackArray<Element>) throws -> R
  ) rethrows -> R {
    var stackArray = allocateUnsafeArray(of: elementType, maximumCapacity: maximumCapacity)
    defer { deallocate(&stackArray) }
    return try body(&stackArray)
  }
}

package struct UnsafeStackArray<Element> {
  private(set) var base: UnsafeMutablePointer<Element>
  fileprivate let capacity: Int
  package private(set) var count = 0

  fileprivate init(base: UnsafeMutablePointer<Element>, capacity: Int) {
    self.base = base
    self.capacity = capacity
  }

  fileprivate mutating func prepareToDeallocate() {
    removeAll()  // Contained elements may need de-init
  }

  // Assume the memory is initialized with whatever is there. Only safe on trivial types.
  mutating func initializeWithContainedGarbage() {
    count = capacity
  }

  package mutating func fill(with element: Element) {
    while count < capacity {
      append(element)
    }
  }

  package mutating func removeAll() {
    base.deinitialize(count: count)
    count = 0
  }

  mutating func append(contentsOf sequence: some Sequence<Element>) {
    for element in sequence {
      append(element)
    }
  }

  package mutating func append(_ element: Element) {
    assert(count < capacity)
    (base + count).initialize(to: element)
    count += 1
  }

  mutating func push(_ element: Element) {
    append(element)
  }

  package mutating func removeLast() {
    assert(count > 0)
    (base + count - 1).deinitialize(count: 1)
    count -= 1
  }

  package subscript(_ index: Int) -> Element {
    get {
      assert(index < count)
      return (base + index).pointee
    }
    set {
      assert(index < count)
      (base + index).pointee = newValue
    }
  }

  package mutating func truncate(to countLimit: Int) {
    assert(countLimit >= 0)
    if count > countLimit {
      (base + countLimit).deinitialize(count: count - countLimit)
      count = countLimit
    }
  }

  mutating func truncateLeavingGarbage(to countLimit: Int) {
    assert(countLimit >= 0)
    count = countLimit
  }

  var contiguousStorage: UnsafeBufferPointer<Element> {
    UnsafeBufferPointer(start: base, count: count)
  }

  func contiguousStorage(count viewCount: Int) -> UnsafeBufferPointer<Element> {
    assert(viewCount <= count)
    return UnsafeBufferPointer(start: base, count: viewCount)
  }
}

extension UnsafeStackArray: RandomAccessCollection {
  package var startIndex: Int {
    0
  }

  package var endIndex: Int {
    count
  }
}

extension UnsafeStackArray: MutableCollection {
}

extension UnsafeStackArray {
  package mutating func popLast() -> Element? {
    let last = last
    if hasContent {
      removeLast()
    }
    return last
  }
}
