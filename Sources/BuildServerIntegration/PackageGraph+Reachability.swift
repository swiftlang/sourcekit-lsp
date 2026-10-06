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

#if !NO_SWIFTPM_DEPENDENCY
@preconcurrency import PackageGraph
@preconcurrency import SourceKitLSPAPI

extension ModulesGraph {
  /// Computes the set of module (target) names that are reachable from root package modules.
  ///
  /// A module is considered reachable if it is part of the dependency graph starting
  /// from the root package's modules. This is used to filter out unreachable modules
  /// from dependencies during background indexing to improve performance.
  ///
  /// - Returns: A set of module names that are reachable from root packages.
  func reachableModuleNames() -> Set<String> {
    Set(reachableModules.map(\.name))
  }
}

extension SourceKitLSPAPI.BuildDescription {
  /// Traverses modules while filtering out unreachable modules from dependencies.
  ///
  /// This method wraps the standard `traverseModules` call but filters out modules
  /// that are not reachable from the root package. Modules from the root package
  /// itself are always included, even if they are not technically reachable,
  /// to ensure complete indexing of the user's own code.
  ///
  /// - Parameters:
  ///   - modulesGraph: The package graph containing reachability information.
  ///   - callback: Closure called for each reachable build target with its parent.
  func traverseReachableModules(
    in modulesGraph: ModulesGraph,
    callback: (any BuildTarget, _ parent: (any BuildTarget)?) -> Void
  ) {
    let reachableModuleNames = modulesGraph.reachableModuleNames()

    self.traverseModules { buildTarget, parent in
      // Always include modules from the root package
      guard !buildTarget.isPartOfRootPackage else {
        callback(buildTarget, parent)
        return
      }

      // For dependency modules, only include them if they are reachable
      guard reachableModuleNames.contains(buildTarget.name) else {
        return
      }

      callback(buildTarget, parent)
    }
  }
}

#endif
