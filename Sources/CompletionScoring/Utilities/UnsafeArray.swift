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

/// A manually allocated and deallocated array with automatic growth on insert.
///
/// - Warning: this type is Unsafe. Writing to an allocated instance must be exclusive to one client.
///   Multiple readers are OK, as long as deallocation is coordinated. Writing must be exclusive because
///   appends can cause realloc, leaving dangling pointers in the copies held by other clients. Appends
///   also would not update the counts in other clients.
internal struct UnsafeArray<Element> {
  private(set) var count = 0
  private(set) var capacity: Int
  private(set) var elements: UnsafeMutablePointer<Element>

  private init(elements: UnsafeMutablePointer<Element>, capacity: Int) {
    self.capacity = capacity
    self.elements = elements
  }

  /// Must be deallocated with `deallocate()`. Will grow beyond `initialCapacity` as elements are added.
  static func allocate(initialCapacity: Int) -> Self {
    Self(elements: UnsafeMutablePointer.allocate(capacity: initialCapacity), capacity: initialCapacity)
  }

  mutating func deallocate() {
    elements.deinitialize(count: count)
    elements.deallocate()
    count = 0
    capacity = 0
  }

  /// Must be deallocated with `deallocate()`.
  func allocateCopy(preservingCapacity: Bool) -> Self {
    var copy = UnsafeArray.allocate(initialCapacity: preservingCapacity ? capacity : count)
    copy.elements.initialize(from: elements, count: count)
    copy.count = count
    return copy
  }

  private mutating func resize(newCapacity: Int) {
    assert(newCapacity >= count)
    elements.resize(fromCount: count, toCount: newCapacity)
    capacity = newCapacity
  }

  mutating func reserve(minimumAdditionalCapacity: Int) {
    let availableAdditionalCapacity = (capacity - count)
    if availableAdditionalCapacity < minimumAdditionalCapacity {
      resize(newCapacity: max(capacity * 2, capacity + minimumAdditionalCapacity))
    }
  }

  mutating func append(_ element: Element) {
    reserve(minimumAdditionalCapacity: 1)
    elements[count] = element
    count += 1
  }

  mutating func append(contentsOf collection: some Collection<Element>) {
    reserve(minimumAdditionalCapacity: collection.count)
    elements.advanced(by: count).initialize(from: collection)
    count += collection.count
  }

  private func assertBounds(_ index: Int) {
    assert(index >= 0)
    assert(index < count)
  }

  subscript(_ index: Int) -> Element {
    get {
      assertBounds(index)
      return elements[index]
    }
    set {
      assertBounds(index)
      elements[index] = newValue
    }
  }
}
