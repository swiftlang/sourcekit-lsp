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

package import Foundation

/// Gathers data from a stdout or stderr pipe. When it has accumulated a full line, calls the handler to handle the
/// string.
package actor PipeAsStringHandler {
  /// Queue on which all data from the pipe will be handled. This allows us to have a
  /// nonisolated `handle` function but ensure that data gets processed in order.
  private let queue = AsyncQueue<Serial>()
  private var buffer = Data()

  /// The closure that actually handles
  private let handler: @Sendable (String) -> Void

  package init(handler: @escaping @Sendable (String) -> Void) {
    self.handler = handler
  }

  deinit {
    if !buffer.isEmpty {
      queue.async { [handler, buffer] in
        handler(String(data: buffer, encoding: .utf8) ?? "<invalid UTF-8>")
      }
    }
  }

  private func handleDataFromPipeImpl(_ newData: Data) {
    self.buffer += newData
    while let newlineIndex = self.buffer.firstIndex(of: UInt8(ascii: "\n")) {
      // Output a separate log message for every line in the pipe.
      // The reason why we don't output multiple lines in a single log message is that
      //  a) os_log truncates log messages at about 1000 bytes. The assumption is that a single line is usually less
      //     than 1000 bytes long but if we merge multiple lines into one message, we might easily exceed this limit.
      //  b) It might be confusing why sometimes a single log message contains one line while sometimes it contains
      //     multiple.
      handler(String(data: self.buffer[...newlineIndex], encoding: .utf8) ?? "<invalid UTF-8>")
      buffer = buffer[buffer.index(after: newlineIndex)...]
    }
  }

  package nonisolated func handleDataFromPipe(_ newData: Data) {
    queue.async {
      await self.handleDataFromPipeImpl(newData)
    }
  }
}
