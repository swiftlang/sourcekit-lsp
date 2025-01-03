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
  struct Corpus {
    let providers: [Provider]
    let patterns: [Pattern]
    let batches: [CandidateBatch]
    let tokenizedInfluencers: [[String]]
    let totalCandidates: Int

    init(patternPrefixLengths: Range<Int>) {
      var randomness = RepeatableRandomNumberGenerator()

      var nextGroupID = 0
      #if DEBUG
      self.providers = [
        Provider.sdkProvider(randomness: &randomness, nextGroupID: &nextGroupID)  // Like SourceKit
      ]
      #else
      self.providers = [
        Provider.sdkProvider(randomness: &randomness, nextGroupID: &nextGroupID),  // Like SourceKit
        Provider.sdkProvider(randomness: &randomness, nextGroupID: &nextGroupID),  // Like SymbolCache
        Provider.sdkProvider(randomness: &randomness, nextGroupID: &nextGroupID),  // Like AllSymbols
        Provider.snippetProvider(randomness: &randomness),
      ]
      #endif
      let symbolGenerator = SymbolGenerator.shared

      self.batches = providers.map(\.batch)
      self.patterns = (0..<10).flatMap { _ -> [Pattern] in
        let patternText = symbolGenerator.randomPatternText(
          lengthRange: patternPrefixLengths,
          using: &randomness
        )
        return (patternPrefixLengths.lowerBound...patternText.count).map { length in
          Pattern(text: String(patternText.prefix(length)))
        }
      }

      self.tokenizedInfluencers = MatchCollator.tokenize(
        influencingTokenizedIdentifiers: [
          "editorController",
          "view",
        ],
        filterLowSignalTokens: true
      )

      self.totalCandidates = providers.map(\.candidates.count).sum()
    }
  }
}
