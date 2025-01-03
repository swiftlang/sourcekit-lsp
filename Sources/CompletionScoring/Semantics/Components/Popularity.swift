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

package struct PopularityScoreComponent: Equatable, Comparable {
  var value: Double
  static let unspecified = PopularityScoreComponent(value: unspecifiedScore)
  static let none = PopularityScoreComponent(value: 1.0)

  package static func < (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.value < rhs.value
  }
}

extension PopularityScoreComponent: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    value = try Double(&decoder)
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    encoder.write(value)
  }
}

package struct Popularity: Equatable, Comparable {
  package var scoreComponent: Double {
    symbolComponent * moduleComponent
  }

  package var symbolComponent: Double

  package var moduleComponent: Double

  // TODO: remove once `PopularityTable` is removed.
  package static let unspecified = Popularity(scoreComponent: unspecifiedScore)
  package static let none = Popularity(scoreComponent: 1.0)

  package enum Category {
    /// Used by `PopularityIndex`, where the popularities don't have much context.
    case index

    /// Used when a client has a lot context. Allowing for a more precise popularity boost.
    case predictive

    private static let predictiveMin = 1.10
    private static let predictiveMax = 1.30

    var minimum: Double {
      switch self {
      case .index:
        return 1.02
      case .predictive:
        return Self.predictiveMin
      }
    }

    var maximum: Double {
      switch self {
      case .index:
        return 1.10
      case .predictive:
        return Self.predictiveMax
      }
    }
  }

  @available(*, deprecated)
  package init(probability: Double) {
    self.init(probability: probability, category: .index)
  }

  /// - Parameter probability: a value in range `0...1`
  package init(probability: Double, category: Category) {
    let score = Self.scoreComponent(probability: probability, category: category)
    self.init(scoreComponent: score)
  }

  /// Takes value in range `0...1`,
  /// and converts to a value that can be used for multiplying with other score components.
  static func scoreComponent(probability: Double, category: Category) -> Double {
    let min = category.minimum
    let max = category.maximum
    if min > max {
      assertionFailure("min \(min) > max \(max)")
      return 1.0
    }
    return (probability * (max - min)) + min
  }

  package init(scoreComponent: Double) {
    self.symbolComponent = scoreComponent
    self.moduleComponent = 1.0
  }

  internal init(symbolComponent: Double, moduleComponent: Double) {
    self.symbolComponent = symbolComponent
    self.moduleComponent = moduleComponent
  }

  package static func < (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.scoreComponent < rhs.scoreComponent
  }
}

extension Popularity: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    symbolComponent = try Double(&decoder)
    moduleComponent = try Double(&decoder)
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    encoder.write(symbolComponent)
    encoder.write(moduleComponent)
  }
}
