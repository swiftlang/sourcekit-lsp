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

import Dispatch
import IndexStoreDB
import LSPLogging
import SKCore
import SKSupport

/// `IndexDelegate` for the SourceKit workspace.
///
/// *Public for testing*.
public actor SourceKitIndexDelegate: IndexDelegate {

  let queue = AsyncQueue<Serial>()

  /// Registered `MainFilesDelegate`s to notify when main files change.
  var mainFilesChangedCallbacks: [@Sendable () async -> Void] = []

  /// The count of pending unit events. Whenever this transitions to 0, it represents a time where
  /// the index finished processing known events. Of course, that may have already changed by the
  /// time we are notified.
  var pendingUnitCount: Int = 0

  public init() {}

  nonisolated public func processingAddedPending(_ count: Int) {
    queue.async {
      await self.addPending(count)
    }
  }

  private func addPending(_ count: Int) {
    pendingUnitCount += count
  }

  nonisolated public func processingCompleted(_ count: Int) {
    queue.async {
      await self.processCompleted(count)
    }
  }

  private func processCompleted(_ count: Int) {
    pendingUnitCount -= count
    if pendingUnitCount == 0 {
      indexChanged()
    }

    if pendingUnitCount < 0 {
      assertionFailure("pendingUnitCount = \(pendingUnitCount) < 0")
      pendingUnitCount = 0
      indexChanged()
    }
  }

  private func indexChanged() {
    logger.debug("IndexStoreDB changed")
    for callback in mainFilesChangedCallbacks {
      queue.async {
        await callback()
      }
    }
  }

  /// Register a delegate to receive notifications when main files change.
  public func addMainFileChangedCallback(_ callback: @escaping @Sendable () async -> Void) {
    mainFilesChangedCallbacks.append(callback)
  }

}
