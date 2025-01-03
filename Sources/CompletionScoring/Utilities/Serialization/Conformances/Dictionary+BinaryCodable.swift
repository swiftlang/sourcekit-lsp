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

extension Dictionary: BinaryCodable where Key: BinaryCodable, Value: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    let count = try Int(&decoder)
    self.init(capacity: count)
    for _ in 0..<count {
      let key = try Key(&decoder)
      let value = try Value(&decoder)
      let previous = self.updateValue(value, forKey: key)
      if let previous = previous {
        throw GenericError("Key collision for \"\(key)\", values: \"\(value)\" vs \"\(previous)\"")
      }
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    encoder.write(count)
    for element in self {
      encoder.write(element.key)
      encoder.write(element.value)
    }
  }
}
