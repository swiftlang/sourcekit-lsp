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

import LanguageServerProtocol
import BuildServerProtocol

extension SourceKitServer {
  
  /// *Public for testing*
  public func _onIndexVisibilityChange(settings: IndexVisibility,
                                       workspace: Workspace,
                                       completion: @escaping ([BuildTargetIdentifier]?) -> Void) {
    queue.async {
      self.onIndexVisibilityChange(settings: settings,
                                   workspace: workspace,
                                   completion: completion)
    }
  }

  /// Must be called on `queue`.
  func onIndexVisibilityChange(settings: IndexVisibility,
                               workspace: Workspace,
                               completion: (([BuildTargetIdentifier]?) -> Void)? = nil) {
    guard workspace.explicitIndexMode else {
      completion?(nil)
      return
    }
    
    if settings.includeTargetDependencies {
      collectTransitiveDependencies(
        targets: settings.targets,
        workspace: workspace) { targets in
          self.limitIndexVisibility(targets: targets,
                                    workspace: workspace,
                                    completion: { completion?(targets) })
      }
    } else {
      self.limitIndexVisibility(targets: settings.targets,
                                workspace: workspace,
                                completion: { completion?(settings.targets) })
    }
  }
  
  func collectTransitiveDependencies(
    targets: [BuildTargetIdentifier],
    workspace: Workspace,
    callback: @escaping ([BuildTargetIdentifier]) -> Void
  ) {
    workspace.buildSystemManager.buildTargets { targetsResponse in
      guard case let .success(targetGraph) = targetsResponse else {
        callback([])
        return
      }
      let targetMap = targetGraph.reduce(into: [BuildTargetIdentifier: BuildTarget]()) {
        $0[$1.id] = $1
      }
      var topLevelTargets = targets
      var transitiveDeps = Set<BuildTargetIdentifier>()
      while !topLevelTargets.isEmpty {
        let targetID = topLevelTargets.removeLast()
        if !transitiveDeps.contains(targetID), let target = targetMap[targetID] {
          topLevelTargets.append(contentsOf: target.dependencies)
        }
        transitiveDeps.insert(targetID)
      }
      callback(Array(transitiveDeps))
    }
  }
  
  func limitIndexVisibility(targets: [BuildTargetIdentifier], workspace: Workspace, completion: @escaping () -> Void) {
    workspace.buildSystemManager.buildTargetOutputPaths(targets: targets) { response in
      guard let items = response.success else { return }
      let currentOutputs = self.schemeOutputs
      let newOutputs = items.reduce(into: Set<URI>()) {
        $0 = $0.union($1.outputPaths)
      }
      self.schemeOutputs = newOutputs
      let outputsToRemove = currentOutputs.subtracting(newOutputs).compactMap {$0.fileURL?.path}
      let outputsToAdd = newOutputs.subtracting(currentOutputs).compactMap {$0.fileURL?.path}
      workspace.index?.removeUnitOutFilePaths(outputsToRemove, waitForProcessing: false)
      workspace.index?.addUnitOutFilePaths(outputsToAdd, waitForProcessing: false)
      completion()
    }
  }
}
