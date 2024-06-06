//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CAtomics

#if compiler(>=6.2)
#warning("We should be able to use atomics in the stdlib when we raise the deployment target to require Swift 6")
#endif

public class AtomicBool {
  private let atomic: UnsafeMutablePointer<CAtomicUInt32>

  public init(initialValue: Bool) {
    self.atomic = atomic_uint32_create(initialValue ? 1 : 0)
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  public var value: Bool {
    get {
      atomic_uint32_get(atomic) != 0
    }
    set {
      atomic_uint32_set(atomic, newValue ? 1 : 0)
    }
  }
}

public class AtomicUInt8 {
  private let atomic: UnsafeMutablePointer<CAtomicUInt32>

  public init(initialValue: UInt8) {
    self.atomic = atomic_uint32_create(UInt32(initialValue))
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  public var value: UInt8 {
    get {
      UInt8(atomic_uint32_get(atomic))
    }
    set {
      atomic_uint32_set(atomic, UInt32(newValue))
    }
  }
}

public class AtomicUInt32 {
  private let atomic: UnsafeMutablePointer<CAtomicUInt32>

  public init(initialValue: UInt32) {
    self.atomic = atomic_uint32_create(initialValue)
  }

  public var value: UInt32 {
    get {
      atomic_uint32_get(atomic)
    }
    set {
      atomic_uint32_set(atomic, newValue)
    }
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  public func fetchAndIncrement() -> UInt32 {
    return atomic_uint32_fetch_and_increment(atomic)
  }
}
