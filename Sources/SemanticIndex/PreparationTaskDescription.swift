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

import BuildServerIntegration
@_spi(SourceKitLSP) package import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

private let preparationIDForLogging = AtomicUInt32(initialValue: 1)

/// Describes a task to prepare a set of targets.
///
/// This task description can be scheduled in a `TaskScheduler`.
package struct PreparationTaskDescription: IndexTaskDescription {
  package static let idPrefix = "prepare"

  package let id = preparationIDForLogging.fetchAndIncrement()

  /// The targets that should be prepared.
  package let targetsToPrepare: [BuildTargetIdentifier]

  /// The build server manager that is used to get the toolchain and build settings for the files to index.
  private let buildServerManager: BuildServerManager

  private let preparationUpToDateTracker: UpToDateTracker<BuildTargetIdentifier, DummySecondaryKey>

  /// See `SemanticIndexManager.logMessageToIndexLog`.
  private let logMessageToIndexLog:
    @Sendable (
      _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
    ) -> Void

  /// Hooks that should be called when the preparation task finishes.
  private let hooks: IndexHooks

  private let purpose: TargetPreparationPurpose

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
    buildServerManager: BuildServerManager,
    preparationUpToDateTracker: UpToDateTracker<BuildTargetIdentifier, DummySecondaryKey>,
    logMessageToIndexLog:
      @escaping @Sendable (
        _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
      ) -> Void,
    hooks: IndexHooks,
    purpose: TargetPreparationPurpose
  ) {
    self.targetsToPrepare = targetsToPrepare
    self.buildServerManager = buildServerManager
    self.preparationUpToDateTracker = preparationUpToDateTracker
    self.logMessageToIndexLog = logMessageToIndexLog
    self.hooks = hooks
    self.purpose = purpose
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
      await hooks.preparationTaskDidStart?(self)

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
        try await buildServerManager.prepare(targets: Set(targetsToPrepare))
      } catch {
        logger.error("Preparation failed: \(error.forLogging)")
      }
      await hooks.preparationTaskDidFinish?(self)
      if !Task.isCancelled {
        await preparationUpToDateTracker.markUpToDate(targetsToPrepare, updateOperationStartDate: startDate)
      }
    }
  }

  package func dependencies(
    to currentlyExecutingTasks: [PreparationTaskDescription]
  ) -> [TaskDependencyAction<PreparationTaskDescription>] {
    return currentlyExecutingTasks.compactMap { (other) -> TaskDependencyAction<PreparationTaskDescription>? in
      if other.purpose == .forIndexing && self.purpose == .forEditorFunctionality {
        // If we're running a background indexing operation but need a target indexed for user interaction,
        // we should prioritize the latter.
        return .cancelAndRescheduleDependency(other)
      }
      return .waitAndElevatePriorityOfDependency(other)
    }
  }
}
