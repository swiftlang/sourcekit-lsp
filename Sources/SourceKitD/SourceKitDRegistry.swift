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

import TSCBasic

/// The set of known SourceKitD instances, uniqued by path.
///
/// It is not generally safe to have two instances of SourceKitD for the same libsourcekitd, so
/// care is taken to ensure that there is only ever one instance per path.
///
/// * To get a new instance, use `getOrAdd("path", create: { NewSourceKitD() })`.
/// * To remove an existing instance, use `remove("path")`, but be aware that if there are any other
///   references to the instances in the program, it can be resurrected if `getOrAdd` is called with
///   the same path. See note on `remove(_:)`
public final class SourceKitDRegistry {

  /// Mutex protecting mutable state in the registry.
  let lock: Lock = Lock()

  /// Mapping from path to active SourceKitD instance.
  var active: [AbsolutePath: SourceKitD] = [:]

  /// Instances that have been unregistered, but may be resurrected if accessed before destruction.
  var cemetary: [AbsolutePath: WeakSourceKitD] = [:]

  /// Initialize an empty registry.
  public init() {}

  /// The global shared SourceKitD registry.
  public static var shared: SourceKitDRegistry = SourceKitDRegistry()

  /// Returns the existing SourceKitD for the given path, or creates it and registers it.
  public func getOrAdd(
    _ key: AbsolutePath,
    create: () throws -> SourceKitD
  ) rethrows -> SourceKitD {
    try lock.withLock {
      if let existing = active[key] {
        return existing
      }
      if let resurrected = cemetary[key]?.value {
        cemetary[key] = nil
        active[key] = resurrected
        return resurrected
      }
      let newValue = try create()
      active[key] = newValue
      return newValue
    }
  }

  /// Removes the SourceKitD instance registered for the given path, if any, from the set of active
  /// instances.
  ///
  /// Since it is not generally safe to have two sourcekitd connections at once, the existing value
  /// is converted to a weak reference until it is no longer referenced anywhere by the program. If
  /// the same path is looked up again before the original service is deinitialized, the original
  /// service is resurrected rather than creating a new instance.
  public func remove(_ key: AbsolutePath) -> SourceKitD? {
    lock.withLock {
      let existing = active.removeValue(forKey: key)
      if let existing = existing {
        assert(self.cemetary[key]?.value == nil)
        cemetary[key] = WeakSourceKitD(value: existing)
      }
      return existing
    }
  }

  /// Remove all SourceKitD instances, including weak ones.
  public func clear() {
    lock.withLock {
      active.removeAll()
      cemetary.removeAll()
    }
  }
}

struct WeakSourceKitD {
  weak var value: SourceKitD?
}
