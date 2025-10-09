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

extension Sequence {
  /// Just like `Sequence.map` but allows an `async` transform function.
  package func asyncMap<T>(
    _ transform: (Element) async throws -> T
  ) async rethrows -> [T] {
    var result: [T] = []
    result.reserveCapacity(self.underestimatedCount)

    for element in self {
      try await result.append(transform(element))
    }

    return result
  }

  /// Just like `Sequence.flatMap` but allows an `async` transform function.
  package func asyncFlatMap<SegmentOfResult: Sequence>(
    _ transform: (Element) async throws -> SegmentOfResult
  ) async rethrows -> [SegmentOfResult.Element] {
    var result: [SegmentOfResult.Element] = []
    result.reserveCapacity(self.underestimatedCount)

    for element in self {
      result += try await transform(element)
    }

    return result
  }

  /// Just like `Sequence.compactMap` but allows an `async` transform function.
  package func asyncCompactMap<T>(
    _ transform: (Element) async throws -> T?
  ) async rethrows -> [T] {
    var result: [T] = []

    for element in self {
      if let transformed = try await transform(element) {
        result.append(transformed)
      }
    }

    return result
  }

  /// Just like `Sequence.map` but allows an `async` transform function.
  package func asyncFilter(
    _ predicate: (Element) async throws -> Bool
  ) async rethrows -> [Element] {
    var result: [Element] = []

    for element in self {
      if try await predicate(element) {
        result.append(element)
      }
    }

    return result
  }

  /// Just like `Sequence.first` but allows an `async` predicate function.
  package func asyncFirst(where predicate: (Element) async throws -> Bool) async rethrows -> Element? {
    for element in self {
      if try await predicate(element) {
        return element
      }
    }

    return nil
  }

  /// Just like `Sequence.contains` but allows an `async` predicate function.
  package func asyncContains(
    where predicate: (Element) async throws -> Bool
  ) async rethrows -> Bool {
    return try await asyncFirst(where: predicate) != nil
  }
}
