//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

package struct BinaryDecoder {
  private let stream: [UInt8]
  private var position = 0

  static let maximumUnderstoodStreamVersion = BinaryEncoder.maximumUnderstoodStreamVersion
  private(set) var contentVersion: Int

  private init(stream: [UInt8]) throws {
    self.stream = stream
    self.contentVersion = 0

    let streamVersion = try Int(&self)
    if streamVersion > Self.maximumUnderstoodStreamVersion {
      throw GenericError("Stream version is too new: \(streamVersion)")
    }
    self.contentVersion = try Int(&self)
  }

  /// Top level function to begin decoding.
  /// - Parameters:
  ///   - body: a closure accepting a `BinaryDecoder` that you can make `init(_:)` calls against to decode the
  ///   archive.
  /// - Returns: The value (if any) returned by the body block.
  static func decode<R>(bytes: [UInt8], _ body: (inout Self) throws -> R) throws -> R {
    var decoder = try BinaryDecoder(stream: bytes)
    let decoded = try body(&decoder)
    if decoder.position != decoder.stream.count {
      // 99% of the time, the client didn't line up their reads and writes, and just decoded garbage. It's more important to catch this than to allow it for some hypothetical use case.
      throw GenericError("Unaligned decode")
    }
    return decoded
  }

  private var bytesRemaining: Int {
    stream.count - position
  }

  // Return the next `byteCount` bytes from the archvie, and advance the read location.
  // Throws if there aren't enough bytes in the archive.
  mutating func readRawBytes(count byteCount: Int) throws -> ArraySlice<UInt8> {
    if bytesRemaining >= byteCount && byteCount >= 0 {
      let slice = stream[position ..+ byteCount]
      position += byteCount
      return slice
    } else {
      throw GenericError("Stream has \(bytesRemaining) bytes renamining, requires \(byteCount)")
    }
  }

  // Return the next byte from the archvie, and advance the read location. Throws if there aren't any more bytes in
  // the archive.
  mutating func readByte() throws -> UInt8 {
    let slice = try readRawBytes(count: 1)
    return slice[slice.startIndex]
  }

  // Read the next bytes from the archive into the memory holding `V`. Useful for decoding primitive values like
  // `UInt32`. All architecture specific constraints like endianness, or sizing, are the responsibility of the caller.
  mutating func read<V>(rawBytesInto result: inout V) throws {
    try withUnsafeMutableBytes(of: &result) { valueBytes in
      let slice = try readRawBytes(count: valueBytes.count)
      for (offset, byte) in slice.enumerated() {
        valueBytes[offset] = byte
      }
    }
  }

  // A convenience method for decoding an enum, and throwing a common error for an unknown case. The body block can
  // decode additional additional payload for data associated with each enum case.
  mutating func decodeEnumByte<E: BinaryCodable>(body: (inout BinaryDecoder, UInt8) throws -> E?) throws -> E {
    let numericRepresentation = try readByte()
    if let decoded = try body(&self, numericRepresentation) {
      return decoded
    } else {
      throw GenericError("Invalid encoding of \(E.self): \(numericRepresentation)")
    }
  }
}
