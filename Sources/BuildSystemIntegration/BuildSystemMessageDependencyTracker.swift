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

import BuildServerProtocol
import LanguageServerProtocol
import SKLogging
import SwiftExtensions

/// A lightweight way of describing tasks that are created from handling BSP
/// requests or notifications for the purpose of dependency tracking.
package enum BuildSystemMessageDependencyTracker: DependencyTracker {
  /// A task that modifies some state. It can thus not be executed concurrently with an request that reads state.
  case stateChange

  /// A task that reads state, such as getting all build targets. These tasks can be run concurrently with other tasks
  /// that read state.
  case stateRead

  /// A task that is responsible for logging information to the client. It can be run concurrently to any state reads
  /// but logging tasks must be ordered among each other.
  case logging

  /// Whether this request needs to finish before `other` can start executing.
  package func isDependency(of other: BuildSystemMessageDependencyTracker) -> Bool {
    switch (self, other) {
    case (.stateChange, _): return true
    case (_, .stateChange): return true
    case (.stateRead, .stateRead): return false
    case (.logging, .logging): return true
    case (.logging, _): return false
    case (_, .logging): return false
    }
  }

  init(_ notification: any NotificationType) {
    switch notification {
    case is DidChangeBuildTargetNotification:
      self = .stateChange
    case is BuildServerProtocol.DidChangeWatchedFilesNotification:
      self = .stateChange
    case is ExitBuildNotification:
      self = .stateChange
    case is FileOptionsChangedNotification:
      self = .stateChange
    case is InitializedBuildNotification:
      self = .stateChange
    case is BuildServerProtocol.LogMessageNotification:
      self = .logging
    default:
      logger.error(
        """
        Unknown notification \(type(of: notification)). Treating as a stateRead notification. \
        This might lead to out-of-order request handling
        """
      )
      self = .stateRead
    }
  }

  init(_ request: any RequestType) {
    switch request {
    case is BuildTargetOutputPaths:
      self = .stateRead
    case is BuildTargetsRequest:
      self = .stateRead
    case is BuildTargetSourcesRequest:
      self = .stateRead
    case is BuildServerProtocol.CreateWorkDoneProgressRequest:
      self = .logging
    case is InitializeBuildRequest:
      self = .stateChange
    case is PrepareTargetsRequest:
      self = .stateRead
    case is RegisterForChanges:
      self = .stateChange
    case is ShutdownBuild:
      self = .stateChange
    case is SourceKitOptionsRequest:
      self = .stateRead
    case is WaitForBuildSystemUpdatesRequest:
      self = .stateChange

    default:
      logger.error(
        """
        Unknown request \(type(of: request)). Treating as a stateRead request. \
        This might lead to out-of-order request handling
        """
      )
      self = .stateRead
    }
  }
}
