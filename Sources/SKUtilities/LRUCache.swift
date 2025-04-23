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

/// A cache that stores key-value pairs up to a given capacity.
///
/// The least recently used key-value pair is removed when the cache exceeds its capacity.
package struct LRUCache<Key: Hashable, Value> {
  private struct Priority {
    var next: Key?
    var previous: Key?

    init(next: Key? = nil, previous: Key? = nil) {
      self.next = next
      self.previous = previous
    }
  }

  // The hash map for accessing cached key-value pairs.
  private var cache: [Key: Value]

  // Doubly linked list of priorities keeping track of the first and last entries.
  private var priorities: [Key: Priority]
  private var firstPriority: Key? = nil
  private var lastPriority: Key? = nil

  /// The maximum number of key-value pairs that can be stored in the cache.
  package let capacity: Int

  /// The number of key-value pairs within the cache.
  package var count: Int { cache.count }

  /// A collection containing just the keys of the cache.
  ///
  /// - Note: Keys will **not** be in the same order that they were added to the cache.
  package var keys: some Collection<Key> { cache.keys }

  /// A collection containing just the values of the cache.
  ///
  /// - Note: Values will **not** be in the same order that they were added to the cache.
  package var values: some Collection<Value> { cache.values }

  package init(capacity: Int) {
    precondition(capacity > 0, "LRUCache capacity must be greater than 0")
    self.capacity = capacity
    self.cache = Dictionary(minimumCapacity: capacity)
    self.priorities = Dictionary(minimumCapacity: capacity)
  }

  /// Adds the given key as the first priority in the doubly linked list of priorities.
  private mutating func addPriority(forKey key: Key) {
    // Make sure the key doesn't already exist in the list
    removePriority(forKey: key)

    guard let currentFirstPriority = firstPriority else {
      firstPriority = key
      lastPriority = key
      priorities[key] = Priority()
      return
    }
    priorities[key] = Priority(next: currentFirstPriority)
    priorities[currentFirstPriority]?.previous = key
    firstPriority = key
  }

  /// Removes the given key from the doubly linked list of priorities.
  private mutating func removePriority(forKey key: Key) {
    guard let priority = priorities.removeValue(forKey: key) else {
      return
    }
    // Update the first and last priorities
    if firstPriority == key {
      firstPriority = priority.next
    }
    if lastPriority == key {
      lastPriority = priority.previous
    }
    // Update the previous and next keys in the priority list
    if let previousPriority = priority.previous {
      priorities[previousPriority]?.next = priority.next
    }
    if let nextPriority = priority.next {
      priorities[nextPriority]?.previous = priority.previous
    }
  }

  /// Removes all key-value pairs from the cache.
  package mutating func removeAll() {
    cache.removeAll()
    priorities.removeAll()
    firstPriority = nil
    lastPriority = nil
  }

  /// Removes all the elements that satisfy the given predicate.
  package mutating func removeAll(where shouldBeRemoved: (_ key: Key) throws -> Bool) rethrows {
    cache = try cache.filter { entry in
      guard try shouldBeRemoved(entry.key) else {
        return true
      }
      removePriority(forKey: entry.key)
      return false
    }
  }

  /// Removes the given key and its associated value from the cache.
  ///
  /// Returns the value that was associated with the key.
  @discardableResult
  package mutating func removeValue(forKey key: Key) -> Value? {
    removePriority(forKey: key)
    return cache.removeValue(forKey: key)
  }

  package subscript(key: Key) -> Value? {
    mutating _read {
      addPriority(forKey: key)
      yield cache[key]
    }
    set {
      guard let newValue else {
        removeValue(forKey: key)
        return
      }
      cache[key] = newValue
      addPriority(forKey: key)
      if cache.count > capacity, let lastPriority {
        removeValue(forKey: lastPriority)
      }
    }
  }
}
