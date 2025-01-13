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

/// Essentially a dictionary where results are asynchronously computed on access.
package class Cache<Key: Sendable & Hashable, Result: Sendable> {
  private var storage: [Key: Task<Result, Error>] = [:]

  package init() {}

  package func get(
    _ key: Key,
    isolation: isolated any Actor,
    compute: @Sendable @escaping (Key) async throws -> Result
  ) async throws -> Result {
    let task: Task<Result, Error>
    if let cached = storage[key] {
      task = cached
    } else {
      task = Task {
        try await compute(key)
      }
      storage[key] = task
    }
    return try await task.value
  }

  /// Get the value cached for `key`. If no value exists for `key`, try deriving the result from an existing cache entry
  /// that satisfies `canReuseKey` by applying `transform` to that result.
  package func getDerived(
    isolation: isolated any Actor,
    _ key: Key,
    canReuseKey: @Sendable @escaping (Key) -> Bool,
    transform: @Sendable @escaping (_ cachedResult: Result) -> Result
  ) async throws -> Result? {
    if let cached = storage[key] {
      // If we have a value for the requested key, prefer that
      return try await cached.value
    }

    // See if don't have an entry for this key, see if we can derive the value from a cached entry.
    for (cachedKey, cachedValue) in storage {
      guard canReuseKey(cachedKey) else {
        continue
      }
      let transformed = Task { try await transform(cachedValue.value) }
      // Cache the transformed result.
      storage[key] = transformed
      return try await transformed.value
    }
    return nil
  }

  package func clear(isolation: isolated any Actor, where condition: (Key) -> Bool) {
    for key in storage.keys {
      if condition(key) {
        storage[key] = nil
      }
    }
  }

  package func clearAll(isolation: isolated any Actor) {
    storage.removeAll()
  }
}
