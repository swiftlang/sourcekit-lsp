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
@_spi(SourceKitLSP) import SKLogging

extension String {
  /// Write this string to the given URL using UTF-8 encoding.
  ///
  /// Sometimes file writes fail on Windows because another process (like sourcekitd or clangd) still has exclusive
  /// access to the file but releases it soon after. Retry to save the file if this happens. This matches what a user
  /// would do.
  package func writeWithRetry(to url: URL) async throws {
    // Depending on the system, mtime resolution might not be perfectly accurate. Particularly containers appear to have
    // imprecise mtimes.
    // Wait a short time period before writing the new file to avoid situations like the following:
    //  - We index a source file and the unit receives a time stamp and wait for indexing to finish
    //  - We modify the source file but so quickly after the unit has been modified that the updated source file
    //    receives the same mtime as the unit file
    //  - We now assume that the we have an up-to-date index for this source file even though we do not.
    //
    // Waiting 10ms appears to be enough to avoid this situation on the systems we care about.
    //
    // Do determine the mtime accuracy on a system, run the following bash commands and look at the time gaps between
    // the time stamps
    // ```
    // mkdir /tmp/dir
    // for x in $(seq 1 1000); do touch /tmp/dir/$x; done
    // for x in /tmp/dir/*; do stat $x; done | grep Modify | sort | uniq
    // ```
    try await Task.sleep(for: .milliseconds(10))

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
