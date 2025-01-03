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

extension Optional: BinaryCodable where Wrapped: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    let hasValue = try Bool(&decoder)
    self = hasValue ? try Wrapped(&decoder) : nil
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    if let value = self {
      encoder.write(true)
      encoder.write(value)
    } else {
      encoder.write(false)
    }
  }
}
