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

package enum SynchronicityCompatibility: Equatable {
  /// Example: sync->sync, async->sync, async->await async
  case compatible

  /// Example: async->async without await
  case convertible

  /// Example: sync->async
  case incompatible

  /// Example: Accessing a type, using a keyword
  case inapplicable

  /// Example: Not confident about either the context, or the target
  case unknown

  /// Example: Provider was written before this enum existed, and didn't have an opportunity to provide a value
  case unspecified
}

extension SynchronicityCompatibility: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    self = try decoder.decodeEnumByte { decoder, n in
      switch n {
      case 0: return .compatible
      case 1: return .convertible
      case 2: return .incompatible
      case 3: return .inapplicable
      case 4: return .unknown
      case 5: return .unspecified
      default: return nil
      }
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    let value: UInt8
    switch self {
    case .compatible: value = 0
    case .convertible: value = 1
    case .incompatible: value = 2
    case .inapplicable: value = 3
    case .unknown: value = 4
    case .unspecified: value = 5
    }
    encoder.write(value)
  }
}
