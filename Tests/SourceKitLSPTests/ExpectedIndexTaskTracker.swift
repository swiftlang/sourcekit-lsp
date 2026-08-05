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
@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import XCTest

enum BuildDestination {
  case host
  case target

  /// A string that can be used to identify the build triple in a `BuildTargetIdentifier`.
  ///
  /// `BuildServerManager.canonicalBuildTargetIdentifier` picks the canonical target based on alphabetical
  /// ordering. We rely on the string "destination" being ordered before "tools" so that we prefer a
  /// `destination` (or "target") target over a `tools` (or "host") target.
  var id: String {
    switch self {
    case .host:
      return "tools"
    case .target:
      return "destination"
    }
  }
}

extension BuildTargetIdentifier {
  // Determine if the BuildTargetIdentifier corresponds to a target with the given name. Matches
  // the formats used by the builtin SwiftPM integration and the SwiftPM BSP implementation.
  func matchesTargetName(_ targetName: String) -> Bool {
    guard let components = URLComponents(url: self.uri.arbitrarySchemeURL, resolvingAgainstBaseURL: false) else {
      return false
    }
    if let value = components.queryItems?.last(where: { $0.name == "target" })?.value {
      return value == targetName
    }
    if let value = components.queryItems?.last(where: { $0.name == "targetGUID" })?.value {
      return value.contains(targetName)
    }
    return false
  }
}

struct ExpectedPreparation {
  let targetName: String

  /// A closure that will be executed when a preparation task starts.
  /// This allows the artificial delay of a preparation task to force two preparation task to race.
  let didStart: (@Sendable () -> Void)?

  /// A closure that will be executed when a preparation task finishes.
  /// This allows the artificial delay of a preparation task to force two preparation task to race.
  let didFinish: (@Sendable () -> Void)?

  internal init(
    targetName: String,
    didStart: (@Sendable () -> Void)? = nil,
    didFinish: (@Sendable () -> Void)? = nil
  ) throws {
    self.targetName = targetName
    self.didStart = didStart
    self.didFinish = didFinish
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

  /// Implicitly-unwrapped optional so we can reference `self` when creating `IndexHooks`.
  /// `nonisolated(unsafe)` is fine because this is not modified after `testHooks` is created.
  nonisolated(unsafe) var testHooks: IndexHooks!

  init(
    expectedPreparations: [[ExpectedPreparation]]? = nil,
    expectedIndexStoreUpdates: [[ExpectedIndexStoreUpdate]]? = nil
  ) {
    self.expectedPreparations = expectedPreparations
    self.expectedIndexStoreUpdates = expectedIndexStoreUpdates
    self.testHooks = IndexHooks(
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

  func preparationTaskDidStart(taskDescription: PreparationTaskDescription) {
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
      if taskDescription.targetsToPrepare.contains(where: { $0.matchesTargetName(expectedPreparation.targetName) }) {
        expectedPreparation.didStart?()
      }
    }
  }

  func preparationTaskDidFinish(taskDescription: PreparationTaskDescription) {
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
    guard
      taskDescription.targetsToPrepare.allSatisfy({ seenTarget in
        expectedTargetsToPrepare.contains(where: { expectedTarget in
          seenTarget.matchesTargetName(expectedTarget.targetName)
        })
      })
    else {
      XCTFail("Received unexpected preparation of \(taskDescription.targetsToPrepare)")
      return
    }
    var remainingExpectedTargetsToPrepare: [ExpectedPreparation] = []
    for expectedPreparation in expectedTargetsToPrepare {
      if taskDescription.targetsToPrepare.contains(where: { $0.matchesTargetName(expectedPreparation.targetName) }) {
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

  func updateIndexStoreTaskDidStart(taskDescription: UpdateIndexStoreTaskDescription) {
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

  func updateIndexStoreTaskDidFinish(taskDescription: UpdateIndexStoreTaskDescription) {
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

fileprivate extension FileAndOutputPath {
  var sourceFileName: String? {
    return self.file.sourceFile.fileURL?.lastPathComponent
  }
}
