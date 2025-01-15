//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring
import Foundation

struct SemanticScoredText {
  var text: String
  var contentType: Candidate.ContentType
  var semanticScore: Double
  var groupID: Int?

  init(_ text: String, groupID: Int? = nil, contentType: Candidate.ContentType = .codeCompletionSymbol) {
    self.text = text
    self.semanticScore = 1.0
    self.groupID = groupID
    self.contentType = contentType
  }

  init(
    _ text: String,
    _ semanticScore: Double,
    groupID: Int? = nil,
    contentType: Candidate.ContentType = .codeCompletionSymbol
  ) {
    self.text = text
    self.semanticScore = semanticScore
    self.groupID = groupID
    self.contentType = contentType
  }

  // Some tests are easier to read in the other order.
  init(_ semanticScore: Double, _ text: String, contentType: Candidate.ContentType = .codeCompletionSymbol) {
    self.text = text
    self.semanticScore = semanticScore
    self.contentType = contentType
  }

  init(
    _ text: String,
    _ classification: SemanticClassification,
    contentType: Candidate.ContentType = .codeCompletionSymbol
  ) {
    self.text = text
    self.semanticScore = classification.score
    self.contentType = contentType
  }
}

extension SemanticClassification {
  static func partial(
    availability: Availability = .inapplicable,
    completionKind: CompletionKind = .other,
    flair: Flair = [],
    moduleProximity: ModuleProximity = .same,
    popularity: Popularity = .none,
    scopeProximity: ScopeProximity = .inapplicable,
    structuralProximity: StructuralProximity = .project(fileSystemHops: 0),
    synchronicityCompatibility: SynchronicityCompatibility = .inapplicable,
    typeCompatibility: TypeCompatibility = .inapplicable
  ) -> Self {
    SemanticClassification(
      availability: availability,
      completionKind: completionKind,
      flair: flair,
      moduleProximity: moduleProximity,
      popularity: popularity,
      scopeProximity: scopeProximity,
      structuralProximity: structuralProximity,
      synchronicityCompatibility: synchronicityCompatibility,
      typeCompatibility: typeCompatibility
    )
  }
}

extension CandidateBatch {
  init(candidates: [SemanticScoredText]) {
    self.init()
    for candidate in candidates {
      append(candidate.text, contentType: candidate.contentType)
    }
  }
}
