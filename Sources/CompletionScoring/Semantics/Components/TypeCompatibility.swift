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

package enum TypeCompatibility: Equatable {
  /// Examples:
  ///  - `String` is compatible with `String`
  ///  - `String` is compatible with `String?`
  ///  - `TextField` is compatible with `View`.
  case compatible

  /// Example: `String` is unrelated to `Int`
  case unrelated

  /// Example: `void` is invalid for `String`
  case invalid

  /// Example: doesn't have a type: a keyword like 'try', or 'while'
  case inapplicable

  /// Example: Failed to type check the expression context
  case unknown

  /// Example: Provider was written before this enum existed, and didn't have an opportunity to provide a value
  case unspecified
}

extension TypeCompatibility {
  ///  This used to penalize producing an `Int` when `Int?` was expected, which isn't correct.
  /// We no longer ask providers to make this distinction
  @available(*, deprecated, renamed: "compatible")
  package static let same = Self.compatible

  /// This used to penalize producing an `Int` when `Int?` was expected, which isn't correct.
  /// We no longer ask providers to make this distinction
  @available(*, deprecated, renamed: "compatible")
  package static let implicitlyConvertible = Self.compatible
}

extension TypeCompatibility: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    self = try decoder.decodeEnumByte { decoder, n in
      switch n {
      case 0: return .compatible
      case 1: return .unrelated
      case 2: return .invalid
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
    case .unrelated: value = 1
    case .invalid: value = 2
    case .inapplicable: value = 3
    case .unknown: value = 4
    case .unspecified: value = 5
    }
    encoder.write(value)
  }
}
