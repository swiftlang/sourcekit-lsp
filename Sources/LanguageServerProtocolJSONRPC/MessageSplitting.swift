//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKSupport

struct MessageHeader: Hashable {
  static let contentLengthKey: [UInt8] = [UInt8]("Content-Length".utf8)
  static let separator: [UInt8] = [UInt8]("\r\n".utf8)
  static let colon: UInt8 = ":".utf8.only!
  static let invalidKeyBytes: [UInt8] = [colon] + separator

  var contentLength: Int? = nil
}

extension RandomAccessCollection where Element == UInt8 {

  /// Returns the first message range and header in `self`, or nil.
  func splitMessage() throws -> ((SubSequence, header: MessageHeader), SubSequence)? {
    guard let (header, rest) = try parseHeader() else { return nil }
    guard let contentLength = header.contentLength else {
      throw MessageDecodingError.parseError("missing Content-Length header")
    }
    if contentLength > rest.count { return nil }
    return ((rest.prefix(contentLength), header: header), rest.dropFirst(contentLength))
  }

  func parseHeader() throws -> (MessageHeader, SubSequence)? {
    var header = MessageHeader()
    var slice = self[...]
    while let (kv, rest) = try slice.parseHeaderField() {
      guard let (key, value) = kv else {
        return (header, rest)
      }
      slice = rest

      if key.elementsEqual(MessageHeader.contentLengthKey) {
        guard let count = Int(ascii: value) else {
          throw MessageDecodingError.parseError("expected integer value in \(String(bytes: value, encoding: .utf8) ?? "<invalid>")")
        }
        header.contentLength = count
      }

      // Unknown field, continue.
    }
    return nil
  }

  func parseHeaderField() throws -> ((key: SubSequence, value: SubSequence)?, SubSequence)? {
    if starts(with: MessageHeader.separator) {
      return (nil, dropFirst(MessageHeader.separator.count))
    } else if first == MessageHeader.separator.first {
      return nil
    }

    guard let keyEnd = firstIndex(where: { MessageHeader.invalidKeyBytes.contains($0) }) else {
      return nil
    }
    if self[keyEnd] != MessageHeader.colon {
      throw MessageDecodingError.parseError("expected ':' in message header")
    }
    let valueStart = index(after:keyEnd)
    guard let valueEnd = self[valueStart...].firstIndex(of: MessageHeader.separator) else {
      return nil
    }

    return ((key: self[..<keyEnd], value: self[valueStart..<valueEnd]), self[index(valueEnd, offsetBy: 2)...])
  }
}
