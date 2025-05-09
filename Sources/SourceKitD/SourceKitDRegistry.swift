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

package import Foundation
import SKLogging

/// The set of known SourceKitD instances, uniqued by path.
///
/// It is not generally safe to have two instances of SourceKitD for the same libsourcekitd, so
/// care is taken to ensure that there is only ever one instance per path.
///
/// * To get a new instance, use `getOrAdd("path", create: { NewSourceKitD() })`.
/// * To remove an existing instance, use `remove("path")`, but be aware that if there are any other
///   references to the instances in the program, it can be resurrected if `getOrAdd` is called with
///   the same path. See note on `remove(_:)`
///
/// `SourceKitDType` is usually `SourceKitD` but can be substituted for a different type for testing purposes.
package actor SourceKitDRegistry<SourceKitDType: AnyObject> {

  /// Mapping from path to active SourceKitD instance.
  private var active: [URL: (pluginPaths: PluginPaths?, sourcekitd: SourceKitDType)] = [:]

  /// Instances that have been unregistered, but may be resurrected if accessed before destruction.
  private var cemetery: [URL: (pluginPaths: PluginPaths?, sourcekitd: WeakSourceKitD<SourceKitDType>)] = [:]

  /// Initialize an empty registry.
  package init() {}

  /// Returns the existing SourceKitD for the given path, or creates it and registers it.
  package func getOrAdd(
    _ key: URL,
    pluginPaths: PluginPaths?,
    create: () throws -> SourceKitDType
  ) async rethrows -> SourceKitDType {
    if let existing = active[key] {
      if existing.pluginPaths != pluginPaths {
        logger.fault(
          "Already created SourceKitD with plugin paths \(existing.pluginPaths?.forLogging), now requesting incompatible plugin paths \(pluginPaths.forLogging)"
        )
      }
      return existing.sourcekitd
    }
    if let resurrected = cemetery[key], let resurrectedSourcekitD = resurrected.sourcekitd.value {
      cemetery[key] = nil
      if resurrected.pluginPaths != pluginPaths {
        logger.fault(
          "Already created SourceKitD with plugin paths \(resurrected.pluginPaths?.forLogging), now requesting incompatible plugin paths \(pluginPaths.forLogging)"
        )
      }
      active[key] = (resurrected.pluginPaths, resurrectedSourcekitD)
      return resurrectedSourcekitD
    }
    let newValue = try create()
    active[key] = (pluginPaths, newValue)
    return newValue
  }

  /// Removes the SourceKitD instance registered for the given path, if any, from the set of active
  /// instances.
  ///
  /// Since it is not generally safe to have two sourcekitd connections at once, the existing value
  /// is converted to a weak reference until it is no longer referenced anywhere by the program. If
  /// the same path is looked up again before the original service is deinitialized, the original
  /// service is resurrected rather than creating a new instance.
  package func remove(_ key: URL) -> SourceKitDType? {
    let existing = active.removeValue(forKey: key)
    if let existing = existing {
      assert(self.cemetery[key]?.sourcekitd.value == nil)
      cemetery[key] = (existing.pluginPaths, WeakSourceKitD(value: existing.sourcekitd))
    }
    return existing?.sourcekitd
  }
}

extension SourceKitDRegistry<SourceKitD> {
  /// The global shared SourceKitD registry.
  package static let shared: SourceKitDRegistry = SourceKitDRegistry()
}

fileprivate struct WeakSourceKitD<SourceKitDType: AnyObject> {
  weak var value: SourceKitDType?
}
