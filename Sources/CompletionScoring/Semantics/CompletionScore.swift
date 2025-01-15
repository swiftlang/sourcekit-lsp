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

/// Represents a composite score formed from a semantic and textual components.
///
/// The textual component forms the bulk of the score typically having a value in the 10's to 100's.
/// You can think of the semantic component as a bonus to the text score.
/// It usually has a value between 0 and 2, and is used as a multiplier.
package struct CompletionScore: Comparable {
  package var semanticComponent: Double
  package var textComponent: Double

  package init(textComponent: Double, semanticComponent: Double) {
    self.semanticComponent = semanticComponent
    self.textComponent = textComponent
  }

  package init(textComponent: Double, semanticClassification: SemanticClassification) {
    self.semanticComponent = semanticClassification.score
    self.textComponent = textComponent
  }

  package var value: Double {
    semanticComponent * textComponent
  }

  package static func < (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.value < rhs.value
  }
}

// MARK: - Deprecated -
extension CompletionScore {
  /// There is no natural order to these arguments, so they're alphabetical.
  @available(
    *,
    deprecated,
    renamed:
      "SemanticClassification(completionKind:deprecationStatus:flair:moduleProximity:popularity:scopeProximity:structuralProximity:synchronicityCompatibility:typeCompatibility:)"
  )
  package static func semanticScore(
    completionKind: CompletionKind,
    deprecationStatus: DeprecationStatus,
    flair: Flair,
    moduleProximity: ModuleProximity,
    popularity: Popularity,
    scopeProximity: ScopeProximity,
    structuralProximity: StructuralProximity,
    synchronicityCompatibility: SynchronicityCompatibility,
    typeCompatibility: TypeCompatibility
  ) -> Double {
    SemanticClassification(
      availability: deprecationStatus,
      completionKind: completionKind,
      flair: flair,
      moduleProximity: moduleProximity,
      popularity: popularity,
      scopeProximity: scopeProximity,
      structuralProximity: structuralProximity,
      synchronicityCompatibility: synchronicityCompatibility,
      typeCompatibility: typeCompatibility
    ).score
  }
}
