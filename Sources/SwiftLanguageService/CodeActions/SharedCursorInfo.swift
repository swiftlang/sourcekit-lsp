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

@_spi(SourceKitLSP) import SKLogging
import SourceKitD

/// Lazy, shared cache for a single `cursorInfo` request across concurrent code action providers.
///
/// The first call to `get()` triggers the sourcekitd request; subsequent calls await the same `Task`.
actor SharedCursorInfo {
  private var cachedTask: Task<(cursorInfo: [CursorInfo], refactorActions: [SemanticRefactorCommand], symbolGraph: String?), any Error>?

  private let fetchCursorInfo: @Sendable (
    ((SKDRequestDictionary) -> Void)?
  ) -> Task<(cursorInfo: [CursorInfo], refactorActions: [SemanticRefactorCommand], symbolGraph: String?), any Error>

  init(
    fetchCursorInfo: @Sendable @escaping (
      ((SKDRequestDictionary) -> Void)?
    ) -> Task<(cursorInfo: [CursorInfo], refactorActions: [SemanticRefactorCommand], symbolGraph: String?), any Error>
  ) {
    self.fetchCursorInfo = fetchCursorInfo
  }

  func get(
    additionalParameters: ((SKDRequestDictionary) -> Void)? = nil
  ) async throws -> (cursorInfo: [CursorInfo], refactorActions: [SemanticRefactorCommand], symbolGraph: String?) {
    if let task = cachedTask {
      return try await task.value
    }
    let task = fetchCursorInfo(additionalParameters)
    cachedTask = task
    return try await task.value
  }
}
