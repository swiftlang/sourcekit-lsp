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

package struct BinaryEncoder {
  private var stream: [UInt8] = []
  static let maximumUnderstoodStreamVersion = 0
  let contentVersion: Int

  private init(contentVersion: Int) {
    self.contentVersion = contentVersion
    write(Self.maximumUnderstoodStreamVersion)
    write(contentVersion)
  }

  /// Top level function to begin encoding.
  /// - Parameters:
  ///   - contentVersion: A version number for the content of the whole archive.
  ///   - body: a closure accepting a `BinaryEncoder` that you can make `write(_:)` calls against to populate the
  ///   archive.
  /// - Returns: a byte array that can be used with `BinaryDecoder`
  static func encode(contentVersion: Int, _ body: (inout Self) -> ()) -> [UInt8] {
    var encoder = BinaryEncoder(contentVersion: contentVersion)
    body(&encoder)
    return encoder.stream
  }

  /// Write the literal bytes of `value` into the archive. The client is responsible for any endian or architecture
  /// sizing considerations.
  mutating func write<V>(rawBytesOf value: V) {
    withUnsafeBytes(of: value) { valueBytes in
      write(rawBytes: valueBytes)
    }
  }

  /// Write `rawBytes` into the archive. You might use this to encode the contents of a bitmap, or a UTF8 sequence.
  mutating func write<C: Collection>(rawBytes: C) where C.Element == UInt8 {
    stream.append(contentsOf: rawBytes)
  }

  mutating func writeByte(_ value: UInt8) {
    write(value)
  }

  /// Recursively encode `value` and all of it's contents.
  mutating func write<V: BinaryCodable>(_ value: V) {
    value.encode(&self)
  }
}
