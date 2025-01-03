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

package protocol OptionSetBinaryCodable: OptionSet & BinaryCodable {
}

extension OptionSetBinaryCodable where RawValue: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    try self.init(rawValue: RawValue(&decoder))
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    encoder.write(rawValue)
  }
}
