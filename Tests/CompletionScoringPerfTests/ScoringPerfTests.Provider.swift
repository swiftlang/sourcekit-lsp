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
import CompletionScoringTestSupport
import Foundation

extension ScoringPerfTests {
  struct Provider {
    let candidates: [Completion]
    let batch: CandidateBatch

    init(candidates: [Completion]) {
      self.candidates = candidates
      self.batch = CandidateBatch(symbols: candidates.map(\.filterText))
    }

    static func sdkProvider(randomness: inout RepeatableRandomNumberGenerator, nextGroupID: inout Int) -> Self {
      let moduleCount = 1 * ScoringPerfTests.scale
      let moduleProximities = WeightedChoices<ModuleProximity>([
        (1 / 16.0, .same),
        (1 / 16.0, .imported(distance: 0)),
        (2 / 16.0, .imported(distance: 1)),
        (4 / 16.0, .imported(distance: 2)),
        (8 / 16.0, .imported(distance: 3)),
      ])

      let modules = Array(count: moduleCount) {
        Module(
          randomness: &randomness,
          moduleProximity: moduleProximities.select(using: &randomness),
          nextGroupID: &nextGroupID
        )
      }
      return Self(candidates: modules.flatMap(\.completions))
    }

    static func snippetProvider(randomness: inout RepeatableRandomNumberGenerator) -> Self {

      return Self(
        candidates: Array(count: 100) {
          let title = SymbolGenerator.shared.randomSegment(using: &randomness, capitalizeFirstTerm: false)
          let classification = SemanticClassification(
            availability: .inapplicable,
            completionKind: .unspecified,
            flair: [],
            moduleProximity: .inapplicable,
            popularity: .none,
            scopeProximity: .inapplicable,
            structuralProximity: .inapplicable,
            synchronicityCompatibility: .inapplicable,
            typeCompatibility: .inapplicable
          )
          return Completion(
            filterText: title,
            displayText: "\(title) - Code Snippet",
            semanticClassification: classification
          )
        }
      )
    }
  }
}
