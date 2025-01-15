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

/// BinaryCodable, along with BinaryEncoder, and BinaryDecoder enable streaming values into a byte array representation.
/// To support BinaryCodable, implement the encode method, and write all of your fields into the coder using
/// `encoder.write()`. In your `init(BinaryDecoder)` method, decode those same fields using `init(BinaryDecoder)`.
///
/// A typical conformance is as simple as:
/// ```
/// struct Size: BinaryCodable {
///     var width: Double
///     var height: Double
///
///     func encode(_ encoder: inout BinaryEncoder) {
///         encoder.write(width)
///         encoder.write(height)
///     }
///
///     init(_ decoder: inout BinaryDecoder) throws {
///         width = try Double(&decoder)
///         height = try Double(&decoder)
///     }
/// }
/// ```
///
/// The encoding is very minimal. There is no metadata in the stream, and decode purely has meaning based on what order
/// clients decode values, and which types they use. If your encoder encodes a bool and two ints, your decoder must
/// decode a bool and two ints, otherwise the next structure to be decoded would read what ever you didn't decode,
/// rather than what it encoded.
package protocol BinaryCodable {

  /// Initialize self using values previously writen in `encode(_:)`. All values written by `encode(_:)` must be read
  /// by `init(_:)`, in the same order, using the same types. Otherwise the next structure to decode will read the
  /// last value you didn't read rather than the first value it wrote.
  init(_ decoder: inout BinaryDecoder) throws

  /// Recursively encode content using `encoder.write(_:)`
  func encode(_ encoder: inout BinaryEncoder)
}

extension BinaryCodable {
  /// Convenience method to encode a structure to a byte array
  package func binaryCodedRepresentation(contentVersion: Int) -> [UInt8] {
    BinaryEncoder.encode(contentVersion: contentVersion) { encoder in
      encoder.write(self)
    }
  }

  /// Convenience method to decode a structure from a byte array
  package init(binaryCodedRepresentation: [UInt8]) throws {
    self = try BinaryDecoder.decode(bytes: binaryCodedRepresentation) { decoder in
      try Self(&decoder)
    }
  }
}
