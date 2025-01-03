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

extension Array: BinaryCodable where Element: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    let count = try Int(&decoder)
    self.init(capacity: count)
    for _ in 0..<count {
      try append(Element(&decoder))
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    encoder.write(count)
    for element in self {
      encoder.write(element)
    }
  }
}
