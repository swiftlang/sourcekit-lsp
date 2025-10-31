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
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// `IndexDelegate` for the SourceKit workspace.
actor SourceKitIndexDelegate: IndexDelegate {
  /// Registered `MainFilesDelegate`s to notify when main files change.
  var mainFilesChangedCallback: @Sendable () async -> Void

  /// The count of pending unit events. Whenever this transitions to 0, it represents a time where
  /// the index finished processing known events. Of course, that may have already changed by the
  /// time we are notified.
  let pendingUnitCount = AtomicInt32(initialValue: 0)

  package init(mainFilesChangedCallback: @escaping @Sendable () async -> Void) {
    self.mainFilesChangedCallback = mainFilesChangedCallback
  }

  nonisolated package func processingAddedPending(_ count: Int) {
    pendingUnitCount.value += Int32(count)
  }

  nonisolated package func processingCompleted(_ count: Int) {
    pendingUnitCount.value -= Int32(count)
    if pendingUnitCount.value == 0 {
      Task {
        await indexChanged()
      }
    }

    if pendingUnitCount.value < 0 {
      // Technically this is not data race safe because `pendingUnitCount` might change between the check and us setting
      // it to 0. But then, this should never happen anyway, so it's fine.
      logger.fault("pendingUnitCount dropped below zero: \(self.pendingUnitCount.value)")
      pendingUnitCount.value = 0
      Task {
        await indexChanged()
      }
    }
  }

  private func indexChanged() async {
    logger.debug("IndexStoreDB changed")
    await mainFilesChangedCallback()
  }
}
