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
  struct Module {
    var completions: [Completion]
    init(
      randomness: inout RepeatableRandomNumberGenerator,
      moduleProximity: ModuleProximity,
      nextGroupID: inout Int
    ) {
      let globalFunctionCount = (5..<50).randomElement(using: &randomness)!
      let globalTypesCount = (5..<250).randomElement(using: &randomness)!
      let weightedAvailability = WeightedChoices<Availability>([
        (0.01, .deprecated),
        (0.05, .unavailable),
        (0.85, .available),
      ])

      let weightedTypeCompatibility = WeightedChoices<TypeCompatibility>([
        (0.10, .invalid),
        (0.05, .compatible),
        (0.85, .unrelated),
      ])

      let functionCompletions: [Completion] = Array(count: globalFunctionCount) {
        let function = SymbolGenerator.shared.randomFunction(using: &randomness)
        let typeCompatibility = weightedTypeCompatibility.select(using: &randomness)
        let availability = weightedAvailability.select(using: &randomness)
        let classification = SemanticClassification(
          availability: availability,
          completionKind: .function,
          flair: [],
          moduleProximity: moduleProximity,
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .inapplicable,
          synchronicityCompatibility: .compatible,
          typeCompatibility: typeCompatibility
        )
        return Completion(
          filterText: function.filterText,
          displayText: function.displayText,
          semanticClassification: classification
        )
      }

      let typeCompletions: [Completion] = Array(count: globalTypesCount) {
        let text = SymbolGenerator.shared.randomType(using: &randomness)
        let typeCompatibility = weightedTypeCompatibility.select(using: &randomness)
        let availability = weightedAvailability.select(using: &randomness)
        let classification = SemanticClassification(
          availability: availability,
          completionKind: .function,
          flair: [],
          moduleProximity: moduleProximity,
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .inapplicable,
          synchronicityCompatibility: .compatible,
          typeCompatibility: typeCompatibility
        )
        let groupID = nextGroupID
        nextGroupID += 1
        return Completion(
          filterText: text,
          displayText: text,
          semanticClassification: classification,
          groupID: groupID
        )
      }

      let initializers: [Completion] = typeCompletions.flatMap { typeCompletion -> [Completion] in
        let initializers = SymbolGenerator.shared.randomInitializers(
          typeName: typeCompletion.filterText,
          using: &randomness
        )
        return initializers.map { initializer -> Completion in
          let typeCompatibility = weightedTypeCompatibility.select(using: &randomness)
          let availability = weightedAvailability.select(using: &randomness)
          let classification = SemanticClassification(
            availability: availability,
            completionKind: .initializer,
            flair: [],
            moduleProximity: moduleProximity,
            popularity: .none,
            scopeProximity: .global,
            structuralProximity: .inapplicable,
            synchronicityCompatibility: .compatible,
            typeCompatibility: typeCompatibility
          )
          return Completion(
            filterText: initializer.filterText,
            displayText: initializer.displayText,
            semanticClassification: classification,
            groupID: typeCompletion.groupID
          )
        }
      }

      self.completions = typeCompletions + functionCompletions + initializers
    }
  }
}
