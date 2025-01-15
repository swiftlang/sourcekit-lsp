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

package enum ScopeProximity: Equatable {
  /// Example: Within the context of a function, a local definition. Could be a variable, or an inner function, type,
  /// etc...
  case local

  /// Example: An argument to a function, including generic parameters
  case argument

  /// Example: Within the context of a class, struct, etc..., possibly nested in a function, references to definitions
  /// at the container level.
  case container

  /// Example: Within the context of a class, struct, etc..., possibly nested in a function, references to definitions
  /// from an inherited class or protocol
  case inheritedContainer

  /// Example: Referring to a type in an outer container, for example, within the iterator for a Sequence, referring to
  /// Element
  case outerContainer

  /// Example: Global variables, free functions, top level types
  case global

  /// Example: Keywords
  case inapplicable

  /// Provider doesn't know the relation between the completion and the context
  case unknown

  /// Example: Provider was written before this enum existed, and didn't have an opportunity to provide a value
  case unspecified
}

extension ScopeProximity: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    self = try decoder.decodeEnumByte { decoder, n in
      switch n {
      case 0: return .local
      case 1: return .argument
      case 2: return .container
      case 3: return .inheritedContainer
      case 4: return .outerContainer
      case 5: return .global
      case 6: return .inapplicable
      case 7: return .unknown
      case 8: return .unspecified
      default: return nil
      }
    }
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    let value: UInt8
    switch self {
    case .local: value = 0
    case .argument: value = 1
    case .container: value = 2
    case .inheritedContainer: value = 3
    case .outerContainer: value = 4
    case .global: value = 5
    case .inapplicable: value = 6
    case .unknown: value = 7
    case .unspecified: value = 8
    }
    encoder.write(value)
  }
}
