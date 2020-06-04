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

import IndexStoreDB
import SKCore
import Dispatch

/// `IndexDelegate` for the SourceKit workspace.
///
/// *Public for testing*.
public final class SourceKitIndexDelegate: IndexDelegate {

  /// Provides mutual exclusion for other members.
  let queue: DispatchQueue = DispatchQueue(label: "\(SourceKitIndexDelegate.self)-queue")

  /// Registered `MainFilesDelegate`s to notify when main files change.
  var mainFilesDelegates: [MainFilesDelegate] = []

  /// The count of pending unit events. Whenever this transitions to 0, it represents a time where
  /// the index finished processing known events. Of course, that may have already changed by the
  /// time we are notified.
  var pendingUnitCount: Int = 0

  public init() {}

  public func processingAddedPending(_ count: Int) {
    queue.sync {
      pendingUnitCount += count
    }
  }

  public func processingCompleted(_ count: Int) {
    queue.sync {
      pendingUnitCount -= count
      if pendingUnitCount == 0 {
        _indexChanged()
      }

      if pendingUnitCount < 0 {
        assertionFailure("pendingUnitCount = \(pendingUnitCount) < 0")
        pendingUnitCount = 0
        _indexChanged()
      }
    }
  }

  /// *Must be called on queue*.
  func _indexChanged() {
    for delegate in mainFilesDelegates {
      delegate.mainFilesChanged()
    }
  }

  /// Register a delegate to receive notifications when main files change.
  public func registerMainFileChanged(_ delegate: MainFilesDelegate) {
    queue.sync {
      mainFilesDelegates.append(delegate)
    }
  }

  /// Un-register a delegate to receive notifications when main files change.
  public func unregisterMainFileChanged(_ delegate: MainFilesDelegate) {
    queue.sync {
      mainFilesDelegates.removeAll(where: { $0 === delegate })
    }
  }
}
