//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKOptions

import struct TSCBasic.ProcessResult

private func numberToEmojis(_ number: Int, numEmojis: Int) -> String {
  let emojis = ["🟥", "🟩", "🟦", "⬜️", "🟪", "⬛️", "🟨", "🟫"]
  var number = abs(number)
  var result = ""
  for _ in 0..<numEmojis {
    let (quotient, remainder) = number.quotientAndRemainder(dividingBy: emojis.count)
    result += emojis[remainder]
    number = quotient
  }
  return result
}

fileprivate extension String {
  /// Returns a two-character emoji string that allows easy differentiation between different task IDs.
  ///
  /// This marker is prepended to every line in the index log.
  var emojiRepresentation: String {
    // Run .hashValue to make sure we semi-randomly pick new emoji markers for new tasks
    return numberToEmojis(self.hashValue, numEmojis: 3)
  }
}

/// Add an emoji hash of the given `taskID` to the start of every line in `message`.
private func prefixMessageWithTaskEmoji(taskID: String, message: String) -> String {
  var message: Substring = message[...]
  while message.last?.isNewline ?? false {
    message = message.dropLast(1)
  }
  let messageWithEmojiLinePrefixes = message.split(separator: "\n", omittingEmptySubsequences: false).map {
    "\(taskID.emojiRepresentation) \($0)"
  }.joined(separator: "\n")
  return messageWithEmojiLinePrefixes
}

extension LogMessageNotification {
  /// If the client does not support the experimental structured logs capability and the `LogMessageNotification`
  /// contains structure, clear it and instead prefix the message with a an emoji sequence that indicates the task it
  /// belongs to.
  func representingTaskIDUsingEmojiPrefixIfNecessary(
    options: SourceKitLSPOptions
  ) -> LogMessageNotification {
    if options.hasExperimentalFeature(.structuredLogs) {
      // Client supports structured logs, nothing to do.
      return self
    }
    var transformed = self
    if let structure = transformed.structure {
      if case .begin(let begin) = structure {
        transformed.message = "\(begin.title)\n\(message)"
      }
      transformed.message = prefixMessageWithTaskEmoji(taskID: structure.taskID, message: transformed.message)
      transformed.structure = nil
    }
    return transformed
  }
}
