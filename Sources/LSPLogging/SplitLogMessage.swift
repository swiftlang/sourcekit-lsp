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
/// The intended use case for this is to split compiler arguments into multiple chunks so that each chunk doesn't exceed
/// the maximum message length of `os_log` and thus won't get truncated.
///
///  - Note: This will only split along newline boundary. If a single line is longer than `maxChunkSize`, it won't be
///    split. This is fine for compiler argument splitting since a single argument is rarely longer than 800 characters.
public func splitLongMultilineMessage(message: String, maxChunkSize: Int = 800) -> [String] {
  var chunks: [String] = []
  for line in message.split(separator: "\n", omittingEmptySubsequences: false) {
    if let lastChunk = chunks.last, lastChunk.utf8.count + line.utf8.count < maxChunkSize {
      chunks[chunks.count - 1] += "\n" + line
    } else {
      chunks.append(String(line))
    }
  }
  return chunks
}
