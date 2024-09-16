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
    isolation: isolated any Actor = #isolation,
    compute: @Sendable @escaping (Key) async throws(Error) -> Result
  ) async throws(Error) -> Result {
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

  package func get(
    whereKey keyPredicate: (Key) -> Bool,
    isolation: isolated any Actor = #isolation,
    transform: @Sendable @escaping (Result) -> Result
  ) async throws -> Result? {
    for (key, value) in storage {
      if keyPredicate(key) {
        return try await transform(value.value)
      }
    }
    return nil
  }

  package func clear(where condition: (Key) -> Bool, isolation: isolated any Actor = #isolation) {
    for key in storage.keys {
      if condition(key) {
        storage[key] = nil
      }
    }
  }

  package func clearAll(isolation: isolated any Actor = #isolation) {
    storage.removeAll()
  }
}
