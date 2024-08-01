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

/// Keeps track of whether an item (a target or file to index) is up-to-date.
actor UpToDateTracker<Item: Hashable> {
  private enum Status {
    /// The item is up-to-date.
    case upToDate

    /// The target or file has been marked out-of-date at the given date.
    ///
    /// Keeping track of the date is necessary so that we don't mark a target as up-to-date if we have the following
    /// ordering of events:
    ///  - Preparation started
    ///  - Target marked out of date
    ///  - Preparation finished
    case outOfDate(Date)
  }

  private var status: [Item: Status] = [:]

  /// Mark the target or file as up-to-date from a preparation/update-indexstore operation started at
  /// `updateOperationStartDate`.
  ///
  /// See comment on `Status.outOfDate` why `updateOperationStartDate` needs to be passed.
  func markUpToDate(_ items: [Item], updateOperationStartDate: Date) {
    for item in items {
      switch status[item] {
      case .upToDate:
        break
      case .outOfDate(let markedOutOfDate):
        if markedOutOfDate < updateOperationStartDate {
          status[item] = .upToDate
        }
      case nil:
        status[item] = .upToDate
      }
    }
  }

  func markOutOfDate(_ items: some Collection<Item>) {
    let date = Date()
    for item in items {
      status[item] = .outOfDate(date)
    }
  }

  func markAllKnownOutOfDate() {
    markOutOfDate(status.keys)
  }

  func isUpToDate(_ item: Item) -> Bool {
    if case .upToDate = status[item] {
      return true
    }
    return false
  }
}
