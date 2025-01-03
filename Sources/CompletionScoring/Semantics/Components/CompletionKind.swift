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

package enum CompletionKind: Equatable {
  /// Example: try, throw, where
  case keyword

  /// Example: A case in an enumeration
  case enumCase

  /// Example: A local, argument, property within a type
  case variable

  /// Example: A function at global scope, or within some other type.
  case function

  /// Example: An init method
  case initializer

  /// Example: in `append(|)`, suggesting `contentsOf:`
  case argumentLabels

  /// Example: `String`, `Int`, generic parameter, typealias, associatedtype
  case type

  /// Example: A `guard let` template for a local variable.
  case template

  /// Example: Foundation, AppKit, UIKit, SwiftUI
  case module

  /// Example: Something not listed here, consider adding a new case
  case other

  /// Example: Completion provider can't even tell what it's offering up.
  case unknown

  /// Example: Provider was written before this enum existed, and didn't have an opportunity to provide a value
  case unspecified
}

extension CompletionKind: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    self = try decoder.decodeEnumByte { decoder, n in
      switch n {
      case 0: return .keyword
      case 1: return .enumCase
      case 2: return .variable
      case 3: return .function
      case 4: return .initializer
      case 5: return .argumentLabels
      case 6: return .type
      case 7: return .template
      case 8: return .other
      case 9: return .unknown
      case 10: return .unspecified
      case 11: return .module
      default: return nil
      }
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    let value: UInt8
    switch self {
    case .keyword: value = 0
    case .enumCase: value = 1
    case .variable: value = 2
    case .function: value = 3
    case .initializer: value = 4
    case .argumentLabels: value = 5
    case .type: value = 6
    case .template: value = 7
    case .other: value = 8
    case .unknown: value = 9
    case .unspecified: value = 10
    case .module: value = 11
    }
    encoder.write(value)
  }
}
