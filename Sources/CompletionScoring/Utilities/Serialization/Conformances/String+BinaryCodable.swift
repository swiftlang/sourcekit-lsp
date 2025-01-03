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

extension String: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    let utf8Bytes = try decoder.readRawBytes(count: Int(&decoder))
    self = try String(bytes: utf8Bytes, encoding: .utf8).unwrap(orThrow: "Invalid UTF8 sequence")
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    withUncachedUTF8Bytes { utf8Bytes in
      encoder.write(utf8Bytes.count)
      encoder.write(rawBytes: utf8Bytes)
    }
  }
}
