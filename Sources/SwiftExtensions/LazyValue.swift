//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A value that is computed on its first access and saved for later retrievals.
package enum LazyValue<T> {
  case computed(T)
  case uninitialized

  /// If the value has already been computed return it, otherwise compute it using `compute`.
  package mutating func cachedValueOrCompute(_ compute: () -> T) -> T {
    switch self {
    case .computed(let value):
      return value
    case .uninitialized:
      let newValue = compute()
      self = .computed(newValue)
      return newValue
    }
  }

  package mutating func reset() {
    self = .uninitialized
  }
}
