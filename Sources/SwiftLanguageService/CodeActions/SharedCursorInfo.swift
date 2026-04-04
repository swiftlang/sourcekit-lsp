//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A lazily-evaluated, shared async value that is computed at most once.
///
/// The first access triggers the operation; subsequent accesses await the same `Task`.
actor AsyncLazy<Success: Sendable> {
  private let operation: @Sendable () async throws -> Success

  init(_ operation: @escaping @Sendable () async throws -> Success) {
    self.operation = operation
  }

  private lazy var task: Task<Success, any Error> = Task {
    try await operation()
  }

  var value: Success {
    get async throws {
      try await task.value
    }
  }
}

typealias SharedCursorInfo = AsyncLazy<CursorInfoResponse>
