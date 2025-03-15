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

import Foundation

struct DummySecondaryKey: Hashable {}

/// Keeps track of whether an item (a target or file to index) is up-to-date.
///
/// The `UpToDateTracker` has two sets of keys. The primary key is the key by which items in the `UpToDateTracker` can
/// be marked as out of date, but only a combination of primary key and secondary key can be marked as up-to-date.
/// This is useful so that we invalidate the index status for a source file's URI (the primary key) when the file
/// receives an update but only mark it up-to-date in with respect to a target (secondary key).
///
/// `DummySecondaryKey` can be used as `SecondaryKey` if the secondary key tracking is not needed.
actor UpToDateTracker<PrimaryKey: Hashable, SecondaryKey: Hashable> {
  private struct Status {
    /// The date at which this primary key has last been marked out-of-date or `nil` if it has never been marked
    /// out-of-date.
    ///
    /// Keeping track of the date is necessary so that we don't mark a target as up-to-date if we have the following
    /// ordering of events:
    ///  - Preparation started
    ///  - Target marked out of date
    ///  - Preparation finished
    var lastOutOfDate: Date?

    /// The secondary keys for which the item is considered up-to-date.
    var secondaryKeys: Set<SecondaryKey>

    internal init(lastOutOfDate: Date? = nil, secondaryKeys: Set<SecondaryKey> = []) {
      self.lastOutOfDate = lastOutOfDate
      self.secondaryKeys = secondaryKeys
    }
  }

  private var status: [PrimaryKey: Status] = [:]

  /// Mark the target or file as up-to-date from a preparation/update-indexstore operation started at
  /// `updateOperationStartDate`.
  ///
  /// See comment on `Status.outOfDate` why `updateOperationStartDate` needs to be passed.
  func markUpToDate(_ items: some Sequence<(PrimaryKey, SecondaryKey)>, updateOperationStartDate: Date) {
    for (primaryKey, secondaryKey) in items {
      if let status = status[primaryKey] {
        if let lastOutOfDate = status.lastOutOfDate, lastOutOfDate > updateOperationStartDate {
          // The key was marked as out-of-date after the operation started. We thus can't mark it as up-to-date again.
          continue
        }
      }
      status[primaryKey, default: Status()].secondaryKeys.insert(secondaryKey)
    }
  }

  func markOutOfDate(_ items: some Sequence<PrimaryKey>) {
    let date = Date()
    for item in items {
      status[item] = Status(lastOutOfDate: date)
    }
  }

  func markAllKnownOutOfDate() {
    markOutOfDate(status.keys)
  }

  func isUpToDate(_ primaryKey: PrimaryKey, _ secondaryKey: SecondaryKey) -> Bool {
    return status[primaryKey]?.secondaryKeys.contains(secondaryKey) ?? false
  }
}

extension UpToDateTracker where SecondaryKey == DummySecondaryKey {
  func markUpToDate(_ items: [PrimaryKey], updateOperationStartDate: Date) {
    self.markUpToDate(items.lazy.map { ($0, DummySecondaryKey()) }, updateOperationStartDate: updateOperationStartDate)
  }

  func isUpToDate(_ primaryKey: PrimaryKey) -> Bool {
    self.isUpToDate(primaryKey, DummySecondaryKey())
  }
}
