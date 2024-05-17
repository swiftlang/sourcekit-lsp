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

/// Callbacks that allow inspection of internal state modifications during testing.
public struct IndexTestHooks: Sendable {
  public var preparationTaskDidFinish: (@Sendable (PreparationTaskDescription) -> Void)?

  /// A callback that is called when an index task finishes.
  public var updateIndexStoreTaskDidFinish: (@Sendable (UpdateIndexStoreTaskDescription) -> Void)?

  public init(
    preparationTaskDidFinish: (@Sendable (PreparationTaskDescription) -> Void)? = nil,
    updateIndexStoreTaskDidFinish: (@Sendable (UpdateIndexStoreTaskDescription) -> Void)? = nil
  ) {
    self.preparationTaskDidFinish = preparationTaskDidFinish
    self.updateIndexStoreTaskDidFinish = updateIndexStoreTaskDidFinish
  }
}
