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

import Foundation
import LanguageServerProtocol
import SKLogging
import SKSupport
import SwiftExtensions

extension WorkDoneProgressManager {
  init?(
    server: SourceKitLSPServer,
    capabilityRegistry: CapabilityRegistry?,
    tokenPrefix: String,
    initialDebounce: Duration? = nil,
    title: String,
    message: String? = nil,
    percentage: Int? = nil
  ) {
    guard let capabilityRegistry, capabilityRegistry.clientCapabilities.window?.workDoneProgress ?? false else {
      return nil
    }
    self.init(
      connectionToClient: server.client,
      waitUntilClientInitialized: { [weak server] in await server?.waitUntilInitialized() },
      tokenPrefix: tokenPrefix,
      initialDebounce: initialDebounce,
      title: title,
      message: message,
      percentage: percentage
    )
  }
}

/// A `WorkDoneProgressManager` that essentially has two states. If any operation tracked by this type is currently
/// running, it displays a work done progress in the client. If multiple operations are running at the same time, it
/// doesn't show multiple work done progress in the client. For example, we only want to show one progress indicator
/// when sourcekitd has crashed, not one per `SwiftLanguageService`.
actor SharedWorkDoneProgressManager {
  private weak var sourceKitLSPServer: SourceKitLSPServer?

  /// The number of in-progress operations. When greater than 0 `workDoneProgress` non-nil and a work done progress is
  /// displayed to the user.
  private var inProgressOperations = 0
  private var workDoneProgress: WorkDoneProgressManager?

  private let tokenPrefix: String
  private let title: String
  private let message: String?

  package init(
    sourceKitLSPServer: SourceKitLSPServer,
    tokenPrefix: String,
    title: String,
    message: String? = nil
  ) {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.tokenPrefix = tokenPrefix
    self.title = title
    self.message = message
  }

  func start() async {
    guard let sourceKitLSPServer else {
      return
    }
    // Do all asynchronous operations up-front so that incrementing `inProgressOperations` and setting `workDoneProgress`
    // cannot be interrupted by an `await` call
    let initialDebounceDuration = await sourceKitLSPServer.options.workDoneProgressDebounceDurationOrDefault
    let capabilityRegistry = await sourceKitLSPServer.capabilityRegistry

    inProgressOperations += 1
    if let capabilityRegistry, workDoneProgress == nil {
      workDoneProgress = WorkDoneProgressManager(
        server: sourceKitLSPServer,
        capabilityRegistry: capabilityRegistry,
        tokenPrefix: tokenPrefix,
        initialDebounce: initialDebounceDuration,
        title: title,
        message: message
      )
    }
  }

  func end() async {
    if inProgressOperations > 0 {
      inProgressOperations -= 1
    } else {
      logger.fault(
        "Unbalanced calls to SharedWorkDoneProgressManager.start and end for \(self.tokenPrefix, privacy: .public)"
      )
    }
    if inProgressOperations == 0, let workDoneProgress {
      self.workDoneProgress = nil
      await workDoneProgress.end()
    }
  }
}
