//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

extension NSLock {
  /// NOTE: Keep in sync with SwiftPM's 'Sources/Basics/NSLock+Extensions.swift'
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

/// A thread safe container that contains a value of type `T`.
///
/// - Note: Unchecked sendable conformance because value is guarded by a lock.
public class ThreadSafeBox<T>: @unchecked Sendable {
  /// Lock guarding `_value`.
  private let lock = NSLock()

  private var _value: T

  public var value: T {
    get {
      return lock.withLock {
        return _value
      }
    }
    set {
      lock.withLock {
        _value = newValue
      }
    }
  }

  public init(initialValue: T) {
    _value = initialValue
  }

  public func withLock<Result>(_ body: (inout T) -> Result) -> Result {
    return lock.withLock {
      return body(&_value)
    }
  }

  /// If the value in the box is an optional, return it and reset it to `nil`
  /// in an atomic operation.
  public func takeValue<U>() -> T where U? == T {
    lock.withLock {
      guard let value = self._value else { return nil }
      self._value = nil
      return value
    }
  }
}
