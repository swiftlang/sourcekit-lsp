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

package enum ModuleProximity: Equatable {
  /// Example: Distance 0 is this module. if you have only "import AppKit", AppKit would be 1, Foundation and
  /// CoreGraphics would be 2.
  case imported(distance: Int)

  /// Example: Referencing NSDocument (AppKit) from a tool only using Foundation. An import to (AppKit) would have to
  /// be added.
  case importable

  /// Example: Keywords
  case inapplicable

  // Completion provider doesn't understand modules
  case unknown

  /// Example: Circular dependency, wrong platform
  case invalid

  /// Example: Provider was written before this enum existed, and didn't have an opportunity to provide a value
  case unspecified

  package static let same = ModuleProximity.imported(distance: 0)
}

extension ModuleProximity: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    self = try decoder.decodeEnumByte { decoder, n in
      switch n {
      case 0: return .imported(distance: try Int(&decoder))
      case 1: return .importable
      case 2: return .inapplicable
      case 3: return .unknown
      case 4: return .invalid
      case 5: return .unspecified
      default: return nil
      }
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    switch self {
    case .imported(let distance):
      encoder.writeByte(0)
      encoder.write(distance)
    case .importable:
      encoder.writeByte(1)
    case .inapplicable:
      encoder.writeByte(2)
    case .unknown:
      encoder.writeByte(3)
    case .invalid:
      encoder.writeByte(4)
    case .unspecified:
      encoder.writeByte(5)
    }
  }
}
