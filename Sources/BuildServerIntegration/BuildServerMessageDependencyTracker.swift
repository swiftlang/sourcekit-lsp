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

@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions

/// A lightweight way of describing tasks that are created from handling BSP
/// requests or notifications for the purpose of dependency tracking.
package enum BuildServerMessageDependencyTracker: QueueBasedMessageHandlerDependencyTracker {
  /// A task that modifies some state. It is a barrier for all requests that read state.
  case stateChange

  /// A task that reads state, such as getting all build targets. These tasks can be run concurrently with other tasks
  /// that read state but needs to wait for all state changes to be handled first.
  case stateRead

  /// A task that is responsible for logging information to the client. They can be run concurrently to any state read
  /// and changes but logging tasks must be ordered among each other.
  case taskProgress

  /// Whether this request needs to finish before `other` can start executing.
  package func isDependency(of other: BuildServerMessageDependencyTracker) -> Bool {
    switch (self, other) {
    case (.stateChange, .stateChange): return true
    case (.stateChange, .stateRead): return true
    case (.stateRead, .stateChange): return true
    case (.stateRead, .stateRead): return false
    case (.taskProgress, .taskProgress): return true
    case (.taskProgress, _): return false
    case (_, .taskProgress): return false
    }
  }

  package init(_ notification: some NotificationType) {
    switch notification {
    case is FileOptionsChangedNotification:
      self = .stateChange
    case is OnBuildExitNotification:
      self = .stateChange
    case is OnBuildInitializedNotification:
      self = .stateChange
    case is OnBuildLogMessageNotification:
      self = .taskProgress
    case is OnBuildTargetDidChangeNotification:
      self = .stateChange
    case is OnWatchedFilesDidChangeNotification:
      self = .stateChange
    case is TaskFinishNotification:
      self = .taskProgress
    case is TaskProgressNotification:
      self = .taskProgress
    case is TaskStartNotification:
      self = .taskProgress
    default:
      logger.error(
        """
        Unknown notification \(type(of: notification)). Treating as a stateChange notification. \
        This might lead to sub-optimal performance because it inhibits parallelism.
        """
      )
      self = .stateRead
    }
  }

  package init(_ request: some RequestType) {
    switch request {
    case is BuildShutdownRequest:
      self = .stateChange
    case is BuildTargetPrepareRequest:
      self = .stateRead
    case is BuildTargetSourcesRequest:
      self = .stateRead
    case is TaskStartNotification, is TaskProgressNotification, is TaskFinishNotification:
      self = .taskProgress
    case is InitializeBuildRequest:
      self = .stateChange
    case is RegisterForChanges:
      self = .stateChange
    case is TextDocumentSourceKitOptionsRequest:
      self = .stateRead
    case is WorkspaceBuildTargetsRequest:
      self = .stateRead
    case is WorkspaceWaitForBuildSystemUpdatesRequest:
      self = .stateRead

    default:
      logger.error(
        """
        Unknown request \(type(of: request)). Treating as a stateChange request. \
        This might lead to sub-optimal performance because it inhibits parallelism.
        """
      )
      self = .stateChange
    }
  }
}
