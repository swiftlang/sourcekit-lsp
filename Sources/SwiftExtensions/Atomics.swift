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

package final class AtomicBool: Sendable {
  private nonisolated(unsafe) let atomic: UnsafeMutablePointer<CAtomicUInt32>

  package init(initialValue: Bool) {
    self.atomic = atomic_uint32_create(initialValue ? 1 : 0)
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  package var value: Bool {
    get {
      atomic_uint32_get(atomic) != 0
    }
    set {
      atomic_uint32_set(atomic, newValue ? 1 : 0)
    }
  }
}

package final class AtomicUInt8: Sendable {
  private nonisolated(unsafe) let atomic: UnsafeMutablePointer<CAtomicUInt32>

  package init(initialValue: UInt8) {
    self.atomic = atomic_uint32_create(UInt32(initialValue))
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  package var value: UInt8 {
    get {
      UInt8(atomic_uint32_get(atomic))
    }
    set {
      atomic_uint32_set(atomic, UInt32(newValue))
    }
  }
}

package final class AtomicUInt32: Sendable {
  private nonisolated(unsafe) let atomic: UnsafeMutablePointer<CAtomicUInt32>

  package init(initialValue: UInt32) {
    self.atomic = atomic_uint32_create(initialValue)
  }

  package var value: UInt32 {
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

  package func fetchAndIncrement() -> UInt32 {
    return atomic_uint32_fetch_and_increment(atomic)
  }
}
