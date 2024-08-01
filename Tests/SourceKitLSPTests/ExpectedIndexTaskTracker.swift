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

import BuildSystemIntegration
import LanguageServerProtocol
import SKLogging
import SemanticIndex
import XCTest

struct ExpectedPreparation {
  let targetID: String
  let runDestinationID: String

  /// A closure that will be executed when a preparation task starts.
  /// This allows the artificial delay of a preparation task to force two preparation task to race.
  let didStart: (@Sendable () -> Void)?

  /// A closure that will be executed when a preparation task finishes.
  /// This allows the artificial delay of a preparation task to force two preparation task to race.
  let didFinish: (@Sendable () -> Void)?

  internal init(
    targetID: String,
    runDestinationID: String,
    didStart: (@Sendable () -> Void)? = nil,
    didFinish: (@Sendable () -> Void)? = nil
  ) {
    self.targetID = targetID
    self.runDestinationID = runDestinationID
    self.didStart = didStart
    self.didFinish = didFinish
  }

  var configuredTarget: ConfiguredTarget {
    return ConfiguredTarget(targetID: targetID, runDestinationID: runDestinationID)
  }
}

struct ExpectedIndexStoreUpdate {
  let sourceFileName: String

  /// A closure that will be executed when a preparation task starts.
  /// This allows the artificial delay of a preparation task to force two preparation task to race.
  let didStart: (() -> Void)?

  /// A closure that will be executed when a preparation task finishes.
  /// This allows the artificial delay of a preparation task to force two preparation task to race.
  let didFinish: (() -> Void)?

  internal init(
    sourceFileName: String,
    didStart: (() -> Void)? = nil,
    didFinish: (() -> Void)? = nil
  ) {
    self.sourceFileName = sourceFileName
    self.didStart = didStart
    self.didFinish = didFinish
  }
}

actor ExpectedIndexTaskTracker {
  /// The targets we expect to be prepared. For targets within the same set, we don't care about the exact order.
  private var expectedPreparations: [[ExpectedPreparation]]?

  private var expectedIndexStoreUpdates: [[ExpectedIndexStoreUpdate]]?

  /// Implicitly-unwrapped optional so we can reference `self` when creating `IndexTestHooks`.
  /// `nonisolated(unsafe)` is fine because this is not modified after `testHooks` is created.
  nonisolated(unsafe) var testHooks: IndexTestHooks!

  init(
    expectedPreparations: [[ExpectedPreparation]]? = nil,
    expectedIndexStoreUpdates: [[ExpectedIndexStoreUpdate]]? = nil
  ) {
    self.expectedPreparations = expectedPreparations
    self.expectedIndexStoreUpdates = expectedIndexStoreUpdates
    self.testHooks = IndexTestHooks(
      preparationTaskDidStart: { [weak self] in
        await self?.preparationTaskDidStart(taskDescription: $0)
      },
      preparationTaskDidFinish: { [weak self] in
        await self?.preparationTaskDidFinish(taskDescription: $0)
      },
      updateIndexStoreTaskDidStart: { [weak self] in
        await self?.updateIndexStoreTaskDidStart(taskDescription: $0)
      },
      updateIndexStoreTaskDidFinish: { [weak self] in
        await self?.updateIndexStoreTaskDidFinish(taskDescription: $0)
      }
    )
  }

  func preparationTaskDidStart(taskDescription: PreparationTaskDescription) -> Void {
    guard let expectedPreparations else {
      return
    }
    if Task.isCancelled {
      logger.debug("Ignoring preparation task start because task is cancelled: \(taskDescription.targetsToPrepare)")
      return
    }
    guard let expectedTargetsToPrepare = expectedPreparations.first else {
      return
    }
    for expectedPreparation in expectedTargetsToPrepare {
      if taskDescription.targetsToPrepare.contains(expectedPreparation.configuredTarget) {
        expectedPreparation.didStart?()
      }
    }
  }

  func preparationTaskDidFinish(taskDescription: PreparationTaskDescription) -> Void {
    guard let expectedPreparations else {
      return
    }
    if Task.isCancelled {
      logger.debug("Ignoring preparation task finish because task is cancelled: \(taskDescription.targetsToPrepare)")
      return
    }
    guard let expectedTargetsToPrepare = expectedPreparations.first else {
      XCTFail("Didn't expect a preparation but received \(taskDescription.targetsToPrepare)")
      return
    }
    guard Set(taskDescription.targetsToPrepare).isSubset(of: expectedTargetsToPrepare.map(\.configuredTarget)) else {
      XCTFail("Received unexpected preparation of \(taskDescription.targetsToPrepare)")
      return
    }
    var remainingExpectedTargetsToPrepare: [ExpectedPreparation] = []
    for expectedPreparation in expectedTargetsToPrepare {
      if taskDescription.targetsToPrepare.contains(expectedPreparation.configuredTarget) {
        expectedPreparation.didFinish?()
      } else {
        remainingExpectedTargetsToPrepare.append(expectedPreparation)
      }
    }
    if remainingExpectedTargetsToPrepare.isEmpty {
      self.expectedPreparations!.remove(at: 0)
    } else {
      self.expectedPreparations![0] = remainingExpectedTargetsToPrepare
    }
  }

  func updateIndexStoreTaskDidStart(taskDescription: UpdateIndexStoreTaskDescription) -> Void {
    if Task.isCancelled {
      logger.debug(
        """
        Ignoring update indexstore start because task is cancelled: \
        \(taskDescription.filesToIndex.map(\.file.sourceFile))
        """
      )
      return
    }
    guard let expectedFilesToIndex = expectedIndexStoreUpdates?.first else {
      return
    }
    for expectedIndexStoreUpdate in expectedFilesToIndex {
      if taskDescription.filesToIndex.contains(where: { $0.sourceFileName == expectedIndexStoreUpdate.sourceFileName })
      {
        expectedIndexStoreUpdate.didStart?()
      }
    }
  }

  func updateIndexStoreTaskDidFinish(taskDescription: UpdateIndexStoreTaskDescription) -> Void {
    guard let expectedIndexStoreUpdates else {
      return
    }
    if Task.isCancelled {
      logger.debug(
        """
        Ignoring update indexstore finish because task is cancelled: \
        \(taskDescription.filesToIndex.map(\.file.sourceFile))
        """
      )
      return
    }
    guard let expectedFilesToIndex = expectedIndexStoreUpdates.first else {
      XCTFail("Didn't expect an index store update but received \(taskDescription.filesToIndex.map(\.file.sourceFile))")
      return
    }
    guard
      Set(taskDescription.filesToIndex.map(\.sourceFileName)).isSubset(of: expectedFilesToIndex.map(\.sourceFileName))
    else {
      XCTFail("Received unexpected index store update of \(taskDescription.filesToIndex.map(\.file.sourceFile))")
      return
    }
    var remainingExpectedFilesToIndex: [ExpectedIndexStoreUpdate] = []
    for expectedIndexStoreUpdate in expectedFilesToIndex {
      if taskDescription.filesToIndex.map(\.sourceFileName).contains(expectedIndexStoreUpdate.sourceFileName) {
        expectedIndexStoreUpdate.didFinish?()
      } else {
        remainingExpectedFilesToIndex.append(expectedIndexStoreUpdate)
      }
    }
    if remainingExpectedFilesToIndex.isEmpty {
      self.expectedIndexStoreUpdates!.remove(at: 0)
    } else {
      self.expectedIndexStoreUpdates![0] = remainingExpectedFilesToIndex
    }
  }

  nonisolated func keepAlive() {
    withExtendedLifetime(self) { _ in }
  }

  deinit {
    if let expectedPreparations = self.expectedPreparations {
      XCTAssert(
        expectedPreparations.isEmpty,
        "ExpectedPreparationTracker destroyed with unfulfilled expected preparations: \(expectedPreparations)."
      )
    }
  }
}

fileprivate extension FileAndTarget {
  var sourceFileName: String? {
    return self.file.sourceFile.fileURL?.lastPathComponent
  }
}
