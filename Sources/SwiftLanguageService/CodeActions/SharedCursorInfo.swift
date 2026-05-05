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

@_spi(SourceKitLSP) import LanguageServerProtocol

/// Request-scoped cache for cursor info requests used by code actions.
actor SharedCursorInfo {
  private let operation: @Sendable (Range<Position>) async throws -> CursorInfoResponse

  private var tasks: [Range<Position>: Task<CursorInfoResponse, any Error>] = [:]

  init(_ operation: @escaping @Sendable (Range<Position>) async throws -> CursorInfoResponse) {
    self.operation = operation
  }

  deinit {
    for task in tasks.values {
      task.cancel()
    }
  }

  func value(for range: Range<Position>) async throws -> CursorInfoResponse {
    let task: Task<CursorInfoResponse, any Error>
    if let existingTask = tasks[range] {
      task = existingTask
    } else {
      let newTask = Task {
        try await operation(range)
      }
      tasks[range] = newTask
      task = newTask
    }

    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}
