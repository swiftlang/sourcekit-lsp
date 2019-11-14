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

public struct JSONRPCMessageHeader: Hashable {
  static let contentLengthKey: [UInt8] = [UInt8]("Content-Length".utf8)
  static let separator: [UInt8] = [UInt8]("\r\n".utf8)
  static let colon: UInt8 = ":".utf8.first!
  static let invalidKeyBytes: [UInt8] = [colon] + separator

  public var contentLength: Int? = nil

  public init(contentLength: Int? = nil) {
    self.contentLength = contentLength
  }
}

extension RandomAccessCollection where Element == UInt8 {

  /// Returns the first message range and header in `self`, or nil.
  public func jsonrpcSplitMessage()
    throws -> ((SubSequence, header: JSONRPCMessageHeader), SubSequence)?
  {
    guard let (header, rest) = try jsonrcpParseHeader() else { return nil }
    guard let contentLength = header.contentLength else {
      throw MessageDecodingError.parseError("missing Content-Length header")
    }
    if contentLength > rest.count { return nil }
    return ((rest.prefix(contentLength), header: header), rest.dropFirst(contentLength))
  }

  public func jsonrcpParseHeader() throws -> (JSONRPCMessageHeader, SubSequence)? {
    var header = JSONRPCMessageHeader()
    var slice = self[...]
    while let (kv, rest) = try slice.jsonrpcParseHeaderField() {
      guard let (key, value) = kv else {
        return (header, rest)
      }
      slice = rest

      if key.elementsEqual(JSONRPCMessageHeader.contentLengthKey) {
        guard let count = Int(ascii: value) else {
          throw MessageDecodingError.parseError("expected integer value in \(String(bytes: value, encoding: .utf8) ?? "<invalid>")")
        }
        header.contentLength = count
      }

      // Unknown field, continue.
    }
    return nil
  }

  public func jsonrpcParseHeaderField() throws -> ((key: SubSequence, value: SubSequence)?, SubSequence)? {
    if starts(with: JSONRPCMessageHeader.separator) {
      return (nil, dropFirst(JSONRPCMessageHeader.separator.count))
    } else if first == JSONRPCMessageHeader.separator.first {
      return nil
    }

    guard let keyEnd = firstIndex(where: { JSONRPCMessageHeader.invalidKeyBytes.contains($0) }) else {
      return nil
    }
    if self[keyEnd] != JSONRPCMessageHeader.colon {
      throw MessageDecodingError.parseError("expected ':' in message header")
    }
    let valueStart = index(after:keyEnd)
    guard let valueEnd = self[valueStart...].firstIndex(of: JSONRPCMessageHeader.separator) else {
      return nil
    }

    return ((key: self[..<keyEnd], value: self[valueStart..<valueEnd]), self[index(valueEnd, offsetBy: 2)...])
  }
}
