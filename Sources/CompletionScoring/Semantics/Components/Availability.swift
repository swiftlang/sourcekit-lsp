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

package enum Availability: Equatable {
  /// Example: Either not tagged, or explicit availability is compatible with current build context
  case available

  /// Example: Explicitly unavailable in current build context - ie, only for another platform.
  case unavailable

  /// Example: deprecated in the future
  case softDeprecated

  /// Example: deprecated in the present, or past
  case deprecated

  /// Completion provider doesn't know if the method is deprecated or not
  case unknown

  /// Example: keyword
  case inapplicable

  /// Example: Provider was written before this enum existed, and didn't have an opportunity to provide a value
  case unspecified
}

extension Availability: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    self = try decoder.decodeEnumByte { decoder, n in
      switch n {
      case 0: return .available
      case 1: return .unavailable
      case 2: return .softDeprecated
      case 3: return .deprecated
      case 4: return .unknown
      case 5: return .inapplicable
      case 6: return .unspecified
      default: return nil
      }
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    let value: UInt8
    switch self {
    case .available: value = 0
    case .unavailable: value = 1
    case .softDeprecated: value = 2
    case .deprecated: value = 3
    case .unknown: value = 4
    case .inapplicable: value = 5
    case .unspecified: value = 6
    }
    encoder.write(value)
  }
}

@available(*, deprecated, renamed: "Availability")
package typealias DeprecationStatus = Availability

extension Availability {
  @available(*, deprecated, renamed: "Availability.available")
  package static let none = DeprecationStatus.available
}
