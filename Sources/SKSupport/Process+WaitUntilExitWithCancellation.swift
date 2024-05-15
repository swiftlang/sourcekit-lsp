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

import class TSCBasic.Process
import struct TSCBasic.ProcessResult

extension Process {
  /// Wait for the process to exit. If the task gets cancelled, during this time, send a `SIGINT` to the process.
  @discardableResult
  public func waitUntilExitSendingSigIntOnTaskCancellation() async throws -> ProcessResult {
    return try await withTaskCancellationHandler {
      try await waitUntilExit()
    } onCancel: {
      signal(SIGINT)
    }
  }
}
