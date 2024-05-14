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
import Foundation
import LSPLogging
import LanguageServerProtocol
import SKCore

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

private var preparationIDForLogging = AtomicUInt32(initialValue: 1)

/// Describes a task to prepare a set of targets.
///
/// This task description can be scheduled in a `TaskScheduler`.
public struct PreparationTaskDescription: IndexTaskDescription {
  public static let idPrefix = "prepare"

  public let id = preparationIDForLogging.fetchAndIncrement()

  /// The targets that should be prepared.
  private let targetsToPrepare: [ConfiguredTarget]

  /// The build system manager that is used to get the toolchain and build settings for the files to index.
  private let buildSystemManager: BuildSystemManager

  /// The task is idempotent because preparing the same target twice produces the same result as preparing it once.
  public var isIdempotent: Bool { true }

  public var estimatedCPUCoreCount: Int { 1 }

  public var description: String {
    return self.redactedDescription
  }

  public var redactedDescription: String {
    return "preparation-\(id)"
  }

  init(
    targetsToPrepare: [ConfiguredTarget],
    buildSystemManager: BuildSystemManager
  ) {
    self.targetsToPrepare = targetsToPrepare
    self.buildSystemManager = buildSystemManager
  }

  public func execute() async {
    // Only use the last two digits of the preparation ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running preparation operations
    await withLoggingScope("preparation-\(id % 100)") {
      let startDate = Date()
      let targetsToPrepare = targetsToPrepare.sorted(by: {
        ($0.targetID, $0.runDestinationID) < ($1.targetID, $1.runDestinationID)
      })
      let targetsToPrepareDescription =
        targetsToPrepare
        .map { "\($0.targetID)-\($0.runDestinationID)" }
        .joined(separator: ", ")
      logger.log(
        "Starting preparation with priority \(Task.currentPriority.rawValue, privacy: .public): \(targetsToPrepareDescription)"
      )
      do {
        try await buildSystemManager.prepare(targets: targetsToPrepare)
      } catch {
        logger.error(
          "Preparation failed: \(error.forLogging)"
        )
      }
      logger.log(
        "Finished preparation in \(Date().timeIntervalSince(startDate) * 1000, privacy: .public)ms: \(targetsToPrepareDescription)"
      )
    }
  }

  public func dependencies(
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
