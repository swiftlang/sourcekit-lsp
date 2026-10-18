//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) import SKLogging
import Synchronization

/// Collects the precompiled modules that index invocations load through explicit module maps, so that the number of
/// variants built for each module can be reported to the index log.
///
/// A module has more than one variant when index invocations of different targets load different builds of it, for
/// example because the targets use different language modes or deployment targets.
package final class ModuleVariantTracker: Sendable {
  /// An entry of an explicit module map, as written by the Swift driver.
  private struct ModuleMapEntry: Decodable {
    let moduleName: String
    let modulePath: String?
    let clangModulePath: String?
  }

  private struct State {
    /// The explicit module maps that have been read.
    var moduleMaps: Set<String> = []

    /// The paths of the variants of each module, keyed by `"<name> (Swift)"` or `"<name> (Clang)"`.
    var variants: [String: Set<String>] = [:]
  }

  private let state = Mutex(State())

  package init() {}

  /// Records the modules loaded through the explicit module map that `arguments` pass to the compiler, if any.
  ///
  /// Each module map is read once: the modules it lists are the same for every invocation that uses it.
  package func recordIndexInvocation(_ arguments: [String]) {
    guard let moduleMap = Self.explicitModuleMap(in: arguments),
      state.withLock({ $0.moduleMaps.insert(moduleMap).inserted })
    else {
      return
    }
    let entries: [ModuleMapEntry]
    do {
      entries = try JSONDecoder().decode([ModuleMapEntry].self, from: Data(contentsOf: URL(fileURLWithPath: moduleMap)))
    } catch {
      logger.error("Failed to read explicit module map \(moduleMap): \(error.forLogging)")
      return
    }
    state.withLock { state in
      for entry in entries {
        if let modulePath = entry.modulePath {
          state.variants["\(entry.moduleName) (Swift)", default: []].insert(modulePath)
        }
        if let clangModulePath = entry.clangModulePath {
          state.variants["\(entry.moduleName) (Clang)", default: []].insert(clangModulePath)
        }
      }
    }
  }

  /// A summary of the module variants recorded since the last call, or `nil` if none were recorded.
  package func takeReport() -> String? {
    let state = self.state.withLock { state in
      defer { state = State() }
      return state
    }
    guard !state.variants.isEmpty else {
      return nil
    }
    let modules = state.variants.sorted {
      ($0.value.count, $1.key) > ($1.value.count, $0.key)
    }
    let variantCount = modules.reduce(0) { $0 + $1.value.count }
    var report =
      "\(modules.count) modules, \(variantCount) variants, from \(state.moduleMaps.count) explicit module maps\n"
    let multiVariantModules = modules.filter { $0.value.count > 1 }
    if !multiVariantModules.isEmpty {
      report += "\nModules with more than one variant:\n"
      for (module, variants) in multiVariantModules {
        report += "  \(module): \(variants.count)\n"
        report += variants.sorted().map { "    \($0)\n" }.joined()
      }
    }
    report += "\nAll modules:\n"
    report += modules.map { "  \($0.key): \($0.value.count)\n" }.joined()
    return report
  }

  /// The explicit module map passed by `arguments`, either directly or through `-Xfrontend`.
  private static func explicitModuleMap(in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: "-explicit-swift-module-map-file") else {
      return nil
    }
    var valueIndex = index + 1
    if valueIndex < arguments.count, arguments[valueIndex] == "-Xfrontend" {
      valueIndex += 1
    }
    guard valueIndex < arguments.count else {
      return nil
    }
    return arguments[valueIndex]
  }
}
