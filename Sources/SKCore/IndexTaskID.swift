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

import struct TSCBasic.ProcessResult

/// The ID of a preparation or update indexstore task. This allows us to log messages from multiple concurrently running
/// indexing tasks to the index log while still being able to differentiate them.
public enum IndexTaskID: Sendable {
  case preparation(id: UInt32)
  case updateIndexStore(id: UInt32)

  private static func numberToEmojis(_ number: Int, numEmojis: Int) -> String {
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

  /// Returns a two-character emoji string that allows easy differentiation between different task IDs.
  ///
  /// This marker is prepended to every line in the index log.
  public var emojiRepresentation: String {
    // Multiply by 2 and optionally add 1 to make sure preparation and update index store have distinct IDs.
    // Run .hashValue to make sure we semi-randomly pick new emoji markers for new tasks
    let numEmojis = 3
    switch self {
    case .preparation(id: let id):
      return Self.numberToEmojis((id * 2).hashValue, numEmojis: numEmojis)
    case .updateIndexStore(id: let id):
      return Self.numberToEmojis((id * 2 + 1).hashValue, numEmojis: numEmojis)
    }
  }
}
