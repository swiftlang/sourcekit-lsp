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

/// A lazily-evaluated, shared async value that is computed at most once.
///
/// The first access triggers the operation; subsequent accesses await the same `Task`.
package actor SharedCursorInfo {
  private let operation: @Sendable () async throws -> CursorInfoResponse

  private var task: Task<CursorInfoResponse, any Error>?

  package init(_ operation: @escaping @Sendable () async throws -> CursorInfoResponse) {
    self.operation = operation
  }

  deinit {
    task?.cancel()
  }

  package var value: CursorInfoResponse {
    get async throws {
      let task: Task<CursorInfoResponse, any Error>
      if let existingTask = self.task {
        task = existingTask
      } else {
        let newTask = Task {
          try await operation()
        }
        self.task = newTask
        task = newTask
      }

      return try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
    }
  }
}
