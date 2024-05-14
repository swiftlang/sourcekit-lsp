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
  func asyncMap<T>(
    @_inheritActorContext _ transform: @Sendable (Element) async throws -> T
  ) async rethrows -> [T] {
    var result: [T] = []
    result.reserveCapacity(self.underestimatedCount)

    for element in self {
      try await result.append(transform(element))
    }

    return result
  }

  /// Just like `Sequence.compactMap` but allows an `async` transform function.
  func asyncCompactMap<T>(
    @_inheritActorContext _ transform: @Sendable (Element) async throws -> T?
  ) async rethrows -> [T] {
    var result: [T] = []

    for element in self {
      if let transformed = try await transform(element) {
        result.append(transformed)
      }
    }

    return result
  }
}
