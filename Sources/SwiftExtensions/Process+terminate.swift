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

extension Foundation.Process {
  /// If the process has not exited after `duration`, terminate it.
  package func terminateIfRunning(after duration: Duration, pollInterval: Duration = .milliseconds(5)) async throws {
    for _ in 0..<Int(duration.seconds / pollInterval.seconds) {
      if !self.isRunning {
        break
      }
      try await Task.sleep(for: pollInterval)
    }
    if self.isRunning {
      self.terminate()
    }
  }

  /// On Posix platforms, send a SIGKILL to the process. On Windows, terminate the process.
  package func terminateImmediately() {
    // TODO: We should also terminate all child processes (https://github.com/swiftlang/sourcekit-lsp/issues/2080)
    #if os(Windows)
    self.terminate()
    #else
    Foundation.kill(processIdentifier, SIGKILL)  // ignore-unacceptable-language
    #endif
  }
}
