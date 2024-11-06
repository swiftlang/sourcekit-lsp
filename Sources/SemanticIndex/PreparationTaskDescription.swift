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

#if compiler(>=6)
package import BuildServerProtocol
import BuildSystemIntegration
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SwiftExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
#else
import BuildServerProtocol
import BuildSystemIntegration
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SwiftExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
#endif

private let preparationIDForLogging = AtomicUInt32(initialValue: 1)

/// Describes a task to prepare a set of targets.
///
/// This task description can be scheduled in a `TaskScheduler`.
package struct PreparationTaskDescription: IndexTaskDescription {
  package static let idPrefix = "prepare"

  package let id = preparationIDForLogging.fetchAndIncrement()

  /// The targets that should be prepared.
  package let targetsToPrepare: [BuildTargetIdentifier]

  /// The build system manager that is used to get the toolchain and build settings for the files to index.
  private let buildSystemManager: BuildSystemManager

  private let preparationUpToDateTracker: UpToDateTracker<BuildTargetIdentifier>

  /// See `SemanticIndexManager.logMessageToIndexLog`.
  private let logMessageToIndexLog: @Sendable (_ taskID: String, _ message: String) -> Void

  /// Test hooks that should be called when the preparation task finishes.
  private let testHooks: IndexTestHooks

  /// The task is idempotent because preparing the same target twice produces the same result as preparing it once.
  package var isIdempotent: Bool { true }

  package var estimatedCPUCoreCount: Int { 1 }

  package var description: String {
    return self.redactedDescription
  }

  package var redactedDescription: String {
    return "preparation-\(id)"
  }

  init(
    targetsToPrepare: [BuildTargetIdentifier],
    buildSystemManager: BuildSystemManager,
    preparationUpToDateTracker: UpToDateTracker<BuildTargetIdentifier>,
    logMessageToIndexLog: @escaping @Sendable (_ taskID: String, _ message: String) -> Void,
    testHooks: IndexTestHooks
  ) {
    self.targetsToPrepare = targetsToPrepare
    self.buildSystemManager = buildSystemManager
    self.preparationUpToDateTracker = preparationUpToDateTracker
    self.logMessageToIndexLog = logMessageToIndexLog
    self.testHooks = testHooks
  }

  package func execute() async {
    // Only use the last two digits of the preparation ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running preparation operations
    await withLoggingSubsystemAndScope(subsystem: indexLoggingSubsystem, scope: "preparation-\(id % 100)") {
      let targetsToPrepare = await targetsToPrepare.asyncFilter { await !preparationUpToDateTracker.isUpToDate($0) }
        // Sort targets to get deterministic ordering. The actual order does not matter.
        .sorted { $0.uri.stringValue < $1.uri.stringValue }
      if targetsToPrepare.isEmpty {
        return
      }
      await testHooks.preparationTaskDidStart?(self)

      let targetsToPrepareDescription = targetsToPrepare.map(\.uri.stringValue).joined(separator: ", ")
      logger.log(
        "Starting preparation with priority \(Task.currentPriority.rawValue, privacy: .public): \(targetsToPrepareDescription)"
      )
      let signposter = Logger(subsystem: LoggingScope.subsystem, category: "preparation").makeSignposter()
      let signpostID = signposter.makeSignpostID()
      let state = signposter.beginInterval("Preparing", id: signpostID, "Preparing \(targetsToPrepareDescription)")
      let startDate = Date()
      defer {
        logger.log(
          "Finished preparation in \(Date().timeIntervalSince(startDate) * 1000, privacy: .public)ms: \(targetsToPrepareDescription)"
        )
        signposter.endInterval("Preparing", state)
      }
      do {
        try await buildSystemManager.prepare(targets: Set(targetsToPrepare))
      } catch {
        logger.error(
          "Preparation failed: \(error.forLogging)"
        )
      }
      await testHooks.preparationTaskDidFinish?(self)
      if !Task.isCancelled {
        await preparationUpToDateTracker.markUpToDate(targetsToPrepare, updateOperationStartDate: startDate)
      }
    }
  }

  package func dependencies(
    to currentlyExecutingTasks: [PreparationTaskDescription]
  ) -> [TaskDependencyAction<PreparationTaskDescription>] {
    return currentlyExecutingTasks.compactMap { (other) -> TaskDependencyAction<PreparationTaskDescription>? in
      if other.targetsToPrepare.count > self.targetsToPrepare.count {
        // If there is an prepare operation with more targets already running, suspend it.
        // The most common use case for this is if we prepare all targets simultaneously during the initial preparation
        // when a project is opened and need a single target indexed for user interaction. We should suspend the
        // workspace-wide preparation and just prepare the currently needed target.
        return .cancelAndRescheduleDependency(other)
      }
      return .waitAndElevatePriorityOfDependency(other)
    }
  }
}
