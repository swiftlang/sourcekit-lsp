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

package enum StructuralProximity: Equatable {
  /// Example: Definition is in Project/Framework/UI/View.swift, usage site is Project/Framework/Model/View.swift,
  /// so hops == 2, up one, and into a sibling. Hops is edit distance where the operations are 'delete, add', not replace.
  case project(fileSystemHops: Int?)

  /// Example: Source of completion is from NSObject.h in the SDK
  case sdk

  /// Example: Keyword
  case inapplicable

  /// Example: Provider doesn't keep track of where definitions come from
  case unknown

  /// Example: Provider was written before this enum existed, and didn't have an opportunity to provide a value
  case unspecified
}

extension StructuralProximity: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    self = try decoder.decodeEnumByte { decoder, n in
      switch n {
      case 0: return .project(fileSystemHops: try Int?(&decoder))
      case 1: return .sdk
      case 2: return .inapplicable
      case 3: return .unknown
      case 4: return .unspecified
      default: return nil
      }
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    switch self {
    case .project(let hops):
      encoder.writeByte(0)
      encoder.write(hops)
    case .sdk: encoder.writeByte(1)
    case .inapplicable: encoder.writeByte(2)
    case .unknown: encoder.writeByte(3)
    case .unspecified: encoder.writeByte(4)
    }
  }
}
