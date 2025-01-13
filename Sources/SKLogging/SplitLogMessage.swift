//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Splits `message` on newline characters such that each chunk is at most `maxChunkSize` bytes long.
///
/// The intended use case for this is to split compiler arguments and a file's contents into multiple chunks so
/// that each chunk doesn't exceed the maximum message length of `os_log` and thus won't get truncated.
///
///  - Note: This will only split along newline boundary. If a single line is longer than `maxChunkSize`, it won't be
///    split. This is fine for compiler argument splitting since a single argument is rarely longer than 800 characters.
package func splitLongMultilineMessage(message: String) -> [String] {
  let maxChunkSize = 800
  var chunks: [String] = []
  for line in message.split(separator: "\n", omittingEmptySubsequences: false) {
    if let lastChunk = chunks.last, lastChunk.utf8.count + line.utf8.count < maxChunkSize {
      chunks[chunks.count - 1] += "\n" + line
    } else {
      if !chunks.isEmpty {
        // Append an end marker to the last chunk so that os_log doesn't truncate trailing whitespace,
        // which would modify the source contents.
        // Empty newlines are important so the offset of the request is correct.
        chunks[chunks.count - 1] += "\n--- End Chunk"
      }
      chunks.append(String(line))
    }
  }
  return chunks
}

extension Logger {
  /// Implementation detail of `logFullObjectInMultipleLogMessages`
  private struct LoggableChunk: CustomLogStringConvertible {
    var description: String
    var redactedDescription: String
  }

  package func logFullObjectInMultipleLogMessages(
    level: LogLevel = .default,
    header: StaticString,
    _ subject: some CustomLogStringConvertible
  ) {
    let chunks = splitLongMultilineMessage(message: subject.description)
    let redactedChunks = splitLongMultilineMessage(message: subject.redactedDescription)
    let maxChunkCount = max(chunks.count, redactedChunks.count)
    for i in 0..<maxChunkCount {
      let loggableChunk = LoggableChunk(
        description: i < chunks.count ? chunks[i] : "",
        redactedDescription: i < redactedChunks.count ? redactedChunks[i] : ""
      )
      self.log(
        level: level,
        """
        \(header, privacy: .public) (\(i + 1)/\(maxChunkCount))
        \(loggableChunk.forLogging)
        """
      )
    }
  }
}
