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

import CompletionScoring
import Foundation

package struct WeightedChoices<T: Sendable>: Sendable {
  package typealias WeightedChoice = (likelihood: Double, value: T)
  private var choices: [T] = []

  package init(_ choices: [WeightedChoice]) {
    precondition(choices.hasContent)
    let smallest = choices.map(\.likelihood).min()!
    let samples = 1.0 / (smallest / 2.0) + 1
    for choice in choices {
      precondition(choice.likelihood > 0)
      precondition(choice.likelihood <= 1.0)
      self.choices.append(contentsOf: Array(repeating: choice.value, count: Int(choice.likelihood * samples)))
    }
  }

  package func select(using randomness: inout RepeatableRandomNumberGenerator) -> T {
    choices.randomElement(using: &randomness)!
  }
}
