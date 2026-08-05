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
class SourceKitIndexDelegate: IndexDelegate {
  let callback: @Sendable () async -> Void

  /// The count of pending unit events. Whenever this transitions to 0, it represents a time where
  /// the index finished processing known events. Of course, that may have already changed by the
  /// time we are notified.
  var pendingUnitCount = 0

  package init(callback: @escaping @Sendable () async -> Void) {
    self.callback = callback
  }

  package func processingAddedPending(_ count: Int) {
    pendingUnitCount += count
  }

  package func processingCompleted(_ count: Int) {
    pendingUnitCount -= count
    if pendingUnitCount == 0 {
      indexChanged()
    }

    if pendingUnitCount < 0 {
      // Technically this is not data race safe because `pendingUnitCount` might change between the check and us setting
      // it to 0. But then, this should never happen anyway, so it's fine.
      logger.fault("pendingUnitCount dropped below zero: \(self.pendingUnitCount)")
      pendingUnitCount = 0
      indexChanged()
    }
  }

  private func indexChanged() {
    Task { [callback] in
      logger.debug("IndexStoreDB changed")
      await callback()
    }
  }
}
