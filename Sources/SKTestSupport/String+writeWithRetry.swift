//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Foundation
import SKLogging

extension String {
  /// Write this string to the given URL using UTF-8 encoding.
  ///
  /// Sometimes file writes fail on Windows because another process (like sourcekitd or clangd) still has exclusive
  /// access to the file but releases it soon after. Retry to save the file if this happens. This matches what a user
  /// would do.
  package func writeWithRetry(to url: URL) async throws {
    #if os(Windows)
    try await repeatUntilExpectedResult(timeout: .seconds(10), sleepInterval: .milliseconds(200)) {
      do {
        try self.write(to: url, atomically: true, encoding: .utf8)
        return true
      } catch {
        logger.error("Writing file contents to \(url) failed, will retry: \(error.forLogging)")
        return false
      }
    }
    #else
    try self.write(to: url, atomically: true, encoding: .utf8)
    #endif
  }
}
