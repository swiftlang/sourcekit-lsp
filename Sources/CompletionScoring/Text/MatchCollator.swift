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

/// Aggregates functionality to support the `MatchCollator.selectBestMatches(for:from:in:)` function, which sorts and
/// selects the best matches from a list, applying the `.thorough` scoring function while being conscience of it's expense.
package struct MatchCollator {
  private var originalMatches: UnsafeBufferPointer<Match>
  private var rescoredMatches: UnsafeMutableBufferPointer<RescoredMatch>
  private let batches: UnsafeBufferPointer<CandidateBatch.UnsafeStorage>
  private let groupScores: UnsafeMutableBufferPointer<Double>
  private let influencers: InfluencingIdentifiers
  private let patternUTF8Length: Int
  private let tieBreaker: UnsafePointer<TieBreaker>
  private let maximumNumberOfItemsForExpensiveSelection: Int
  package static let defaultMaximumNumberOfItemsForExpensiveSelection = 100

  private init(
    originalMatches: UnsafeBufferPointer<Match>,
    rescoredMatches: UnsafeMutableBufferPointer<MatchCollator.RescoredMatch>,
    batches: UnsafeBufferPointer<CandidateBatch.UnsafeStorage>,
    groupScores: UnsafeMutableBufferPointer<Double>,
    influencers: InfluencingIdentifiers,
    patternUTF8Length: Int,
    orderingTiesBy tieBreaker: UnsafePointer<TieBreaker>,
    maximumNumberOfItemsForExpensiveSelection: Int
  ) {
    for match in originalMatches {
      precondition(batches.indices.contains(match.batchIndex))
      precondition(batches[match.batchIndex].indices.contains(match.candidateIndex))
    }
    self.originalMatches = originalMatches
    self.rescoredMatches = rescoredMatches
    self.batches = batches
    self.groupScores = groupScores
    self.influencers = influencers
    self.patternUTF8Length = patternUTF8Length
    self.tieBreaker = tieBreaker
    self.maximumNumberOfItemsForExpensiveSelection = maximumNumberOfItemsForExpensiveSelection
  }

  private static func withUnsafeMatchCollator<R>(
    matches originalMatches: [Match],
    batches: [CandidateBatch],
    influencingTokenizedIdentifiers: [[String]],
    patternUTF8Length: Int,
    orderingTiesBy tieBreakerBody: (_ lhs: Match, _ rhs: Match) -> Bool,
    maximumNumberOfItemsForExpensiveSelection: Int,
    body: (inout MatchCollator) -> R
  ) -> R {
    let rescoredMatches = UnsafeMutableBufferPointer<RescoredMatch>.allocate(capacity: originalMatches.count)
    defer { rescoredMatches.deinitializeAllAndDeallocate() }
    let groupScores = UnsafeMutableBufferPointer<Double>.allocate(capacity: originalMatches.count)
    defer { groupScores.deinitializeAllAndDeallocate() }
    for (matchIndex, originalMatch) in originalMatches.enumerated() {
      rescoredMatches.initialize(
        index: matchIndex,
        to: RescoredMatch(
          originalMatchIndex: matchIndex,
          textIndex: TextIndex(batch: originalMatch.batchIndex, candidate: originalMatch.candidateIndex),
          denseGroupID: nil,
          individualScore: originalMatch.score,
          groupScore: -Double.infinity,
          falseStarts: 0
        )
      )
    }
    assignDenseGroupId(to: rescoredMatches, from: originalMatches, batchCount: batches.count)
    return withoutActuallyEscaping(tieBreakerBody) { tieBreakerBody in
      var tieBreaker = TieBreaker(tieBreakerBody)
      return withExtendedLifetime(tieBreaker) {
        InfluencingIdentifiers.withUnsafeInfluencingTokenizedIdentifiers(influencingTokenizedIdentifiers) {
          influencers in
          originalMatches.withUnsafeBufferPointer { originalMatches in
            CandidateBatch.withUnsafeStorages(batches) { batchStorages in
              var collator = Self(
                originalMatches: originalMatches,
                rescoredMatches: rescoredMatches,
                batches: batchStorages,
                groupScores: groupScores,
                influencers: influencers,
                patternUTF8Length: patternUTF8Length,
                orderingTiesBy: &tieBreaker,
                maximumNumberOfItemsForExpensiveSelection: maximumNumberOfItemsForExpensiveSelection
              )
              return body(&collator)
            }
          }
        }
      }
    }
  }

  /// This allows us to only take the dictionary hit one time, so that we don't have to do repeated dictionary lookups
  /// as we lookup groupIDs and map them to group scores.
  private static func assignDenseGroupId(
    to rescoredMatches: UnsafeMutableBufferPointer<RescoredMatch>,
    from originalMatches: [Match],
    batchCount: Int
  ) {
    typealias SparseGroupID = Int
    typealias DenseGroupID = Int
    let initialDictionaryCapacity = (batchCount > 0) ? originalMatches.count / batchCount : 0
    var batchAssignments: [[SparseGroupID: DenseGroupID]] = Array(
      repeating: Dictionary(capacity: initialDictionaryCapacity),
      count: batchCount
    )
    var nextDenseID = 0
    for (matchIndex, match) in originalMatches.enumerated() {
      if let sparseID = match.groupID {
        rescoredMatches[matchIndex].denseGroupID = batchAssignments[match.batchIndex][sparseID].lazyInitialize {
          let denseID = nextDenseID
          nextDenseID += 1
          return denseID
        }
      }
    }
  }

  private mutating func selectBestFastScoredMatchesForThoroughScoring() {
    if rescoredMatches.count > maximumNumberOfItemsForExpensiveSelection {
      rescoredMatches.selectTopKAndTruncate(maximumNumberOfItemsForExpensiveSelection) { lhs, rhs in
        (lhs.groupScore >? rhs.groupScore) ?? (lhs.individualScore > rhs.individualScore)
      }
    }
  }

  private func refreshGroupScores() {
    // We call this the first time without initializing the Double values.
    groupScores.setAll(to: -.infinity)
    for match in rescoredMatches {
      if let denseGroupID = match.denseGroupID {
        groupScores[denseGroupID] = max(groupScores[denseGroupID], match.individualScore.value)
      }
    }
    for (index, match) in rescoredMatches.enumerated() {
      if let denseGroupID = match.denseGroupID {
        rescoredMatches[index].groupScore = groupScores[denseGroupID]
      } else {
        rescoredMatches[index].groupScore = rescoredMatches[index].individualScore.value
      }
    }
  }

  private func unsafeBytes(at textIndex: TextIndex) -> CandidateBatch.UTF8Bytes {
    return batches[textIndex.batch].bytes(at: textIndex.candidate)
  }

  mutating func thoroughlyRescore(pattern: Pattern) {
    // `nonisolated(unsafe)` is fine because every iteration accesses a different index of `batches`.
    nonisolated(unsafe) let batches = batches
    // `nonisolated(unsafe)` is fine because every iteration accesses a disjunct set of indices of `rescoredMatches`.
    nonisolated(unsafe) let rescoredMatches = rescoredMatches
    let pattern = pattern
    rescoredMatches.slicedConcurrentForEachSliceRange { sliceRange in
      UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
        for matchIndex in sliceRange {
          let textIndex = rescoredMatches[matchIndex].textIndex
          let (candidateBytes, candidateContentType) = batches[textIndex.batch]
            .candidateContent(at: textIndex.candidate)
          let textScore = pattern.score(
            candidate: candidateBytes,
            contentType: candidateContentType,
            precision: .thorough,
            allocator: &allocator
          )
          rescoredMatches[matchIndex].individualScore.textComponent = textScore.value
          rescoredMatches[matchIndex].falseStarts = textScore.falseStarts
        }
      }
    }
  }

  /// Generated and validated by `MatchCollatorTests.testMinimumTextCutoff()`
  package static let bestRejectedTextScoreByPatternLength: [Double] = [
    0.0,
    0.0,
    2.900400881379344,
    2.900400881379344,
    2.900400881379344,
    2.900400881379344,
    2.900400881379344,
    2.900400881379344,
    2.900400881379344,
    2.900400881379344,
    2.900400881379344,
  ]

  private var cutoffRatio: Double {
    //      |
    // 0.67 |  ____________________
    //      | /
    //      |/
    //      +------------------------
    //         4
    let fullCutoffRatio = (2.0 / 3.0)
    let weight = min(max(Double(patternUTF8Length), 1.0) / 4.0, 1.0)
    return fullCutoffRatio * weight
  }

  private static let maxInfluenceBonus = 0.10

  private static let maxFalseStarts = 2

  private var bestRejectedTextScore: Double {
    let bestRejectedTextScoreByPatternLength = Self.bestRejectedTextScoreByPatternLength
    let inBounds = bestRejectedTextScoreByPatternLength.indices.contains(patternUTF8Length)
    return
      (inBounds
      ? bestRejectedTextScoreByPatternLength[patternUTF8Length] : bestRejectedTextScoreByPatternLength.last)
      ?? 0
  }

  private mutating func selectBestThoroughlyScoredMatches() {
    if let bestThoroughlyScoredMatch = rescoredMatches.max(by: \.individualScore) {
      let topMatchFalseStarts = bestThoroughlyScoredMatch.falseStarts
      let compositeCutoff = self.cutoffRatio * bestThoroughlyScoredMatch.individualScore.value
      let semanticCutoffForTokenFalseStartsExemption =
        bestThoroughlyScoredMatch.individualScore.semanticComponent / 3.0
      let bestRejectedTextScore = bestRejectedTextScore
      let maxAllowedFalseStarts = Self.maxFalseStarts
      rescoredMatches.removeAndTruncateWhere { candidate in
        let overcomesTextCutoff = candidate.individualScore.textComponent > bestRejectedTextScore
        let overcomesFalseStartCutoff = candidate.falseStarts <= maxAllowedFalseStarts
        let acceptedByCompositeScore = candidate.individualScore.value >= compositeCutoff
        let acceptedByTokenFalseStarts =
          (candidate.falseStarts <= topMatchFalseStarts)
          && (candidate.individualScore.semanticComponent >= semanticCutoffForTokenFalseStartsExemption)
        let keep =
          overcomesTextCutoff && overcomesFalseStartCutoff
          && (acceptedByCompositeScore || acceptedByTokenFalseStarts)
        return !keep
      }
    }
  }

  private mutating func selectBestFastScoredMatches() {
    if let bestSemanticScore = rescoredMatches.max(of: { candidate in candidate.individualScore.semanticComponent }) {
      let minimumSemanticScore = bestSemanticScore * cutoffRatio
      rescoredMatches.removeAndTruncateWhere { candidate in
        candidate.individualScore.semanticComponent < minimumSemanticScore
      }
    }
  }

  private mutating func applyInfluence() {
    let influencers = self.influencers
    let maxInfluenceBonus = Self.maxInfluenceBonus
    if influencers.hasContent && (maxInfluenceBonus != 0.0) {
      // `nonisolated(unsafe)` is fine because every iteration accesses a disjoint set of indices in `rescoredMatches`.
      nonisolated(unsafe) let rescoredMatches = rescoredMatches
      // `nonisolated(unsafe)` is fine because `batches` is not modified
      nonisolated(unsafe) let batches = batches
      rescoredMatches.slicedConcurrentForEachSliceRange { sliceRange in
        UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
          for matchIndex in sliceRange {
            let textIndex = rescoredMatches[matchIndex].textIndex
            let candidate = batches[textIndex.batch].candidate(at: textIndex.candidate)
            let percentOfInfluenceBonus = influencers.score(candidate: candidate, allocator: &allocator)
            let textCoefficient = (percentOfInfluenceBonus * maxInfluenceBonus) + 1.0
            rescoredMatches[matchIndex].individualScore.textComponent *= textCoefficient
          }
        }
      }
      refreshGroupScores()
    }
  }

  private func lessThan(_ lhs: RescoredMatch, _ rhs: RescoredMatch) -> Bool {
    if let definitiveGroupScoreComparison = lhs.groupScore >? rhs.groupScore {
      return definitiveGroupScoreComparison
      // Only compare `individualScore` within the same group, or among items that have no group.
      // Otherwise when the group score ties, we would interleave the members of the tying groups.
    } else if (lhs.denseGroupID == rhs.denseGroupID),
      let definitiveIndividualScoreComparison = lhs.individualScore.value >? rhs.individualScore.value
    {
      return definitiveIndividualScoreComparison
    } else {
      let lhsBytes = unsafeBytes(at: lhs.textIndex)
      let rhsBytes = unsafeBytes(at: rhs.textIndex)
      switch compareBytes(lhsBytes, rhsBytes) {
      case .ascending:
        return true
      case .descending:
        return false
      case .same:
        if rescoredMatches.count <= maximumNumberOfItemsForExpensiveSelection {
          let lhsOriginal = originalMatches[lhs.originalMatchIndex]
          let rhsOriginal = originalMatches[rhs.originalMatchIndex]
          if tieBreaker.pointee.lessThan(lhsOriginal, rhsOriginal) {
            return true
          } else if tieBreaker.pointee.lessThan(rhsOriginal, lhsOriginal) {
            return false
          }
        }
        return (lhs.originalMatchIndex < rhs.originalMatchIndex)
      }
    }
  }

  private mutating func sort() {
    rescoredMatches.sort(by: lessThan)
  }

  private mutating func selectBestMatches(pattern: Pattern) -> Selection {
    refreshGroupScores()
    let precision: Pattern.Precision
    if pattern.typedEnoughForThoroughScoring
      || (rescoredMatches.count <= maximumNumberOfItemsForExpensiveSelection)
    {
      selectBestFastScoredMatchesForThoroughScoring()
      thoroughlyRescore(pattern: pattern)
      refreshGroupScores()
      selectBestThoroughlyScoredMatches()
      precision = .thorough
    } else {
      selectBestFastScoredMatches()
      precision = .fast
    }
    applyInfluence()
    sort()
    return Selection(
      precision: precision,
      matches: rescoredMatches.map { match in
        originalMatches[match.originalMatchIndex]
      }
    )
  }

  /// Uses heuristics to cull matches, and then apply the expensive `.thorough` scoring function.
  ///
  /// Returns the results stably ordered by score, then text.
  package static func selectBestMatches(
    _ matches: [Match],
    from batches: [CandidateBatch],
    for pattern: Pattern,
    influencingTokenizedIdentifiers: [[String]],
    orderingTiesBy tieBreaker: (_ lhs: Match, _ rhs: Match) -> Bool,
    maximumNumberOfItemsForExpensiveSelection: Int
  ) -> Selection {
    withUnsafeMatchCollator(
      matches: matches,
      batches: batches,
      influencingTokenizedIdentifiers: influencingTokenizedIdentifiers,
      patternUTF8Length: pattern.patternUTF8Length,
      orderingTiesBy: tieBreaker,
      maximumNumberOfItemsForExpensiveSelection: maximumNumberOfItemsForExpensiveSelection
    ) { collator in
      collator.selectBestMatches(pattern: pattern)
    }
  }

  /// Short for `selectBestMatches(_:from:for:influencingTokenizedIdentifiers:orderingTiesBy:).matches`
  package static func selectBestMatches(
    for pattern: Pattern,
    from matches: [Match],
    in batches: [CandidateBatch],
    influencingTokenizedIdentifiers: [[String]],
    orderingTiesBy tieBreaker: (_ lhs: Match, _ rhs: Match) -> Bool,
    maximumNumberOfItemsForExpensiveSelection: Int = Self.defaultMaximumNumberOfItemsForExpensiveSelection
  ) -> [Match] {
    return selectBestMatches(
      matches,
      from: batches,
      for: pattern,
      influencingTokenizedIdentifiers: influencingTokenizedIdentifiers,
      orderingTiesBy: tieBreaker,
      maximumNumberOfItemsForExpensiveSelection: maximumNumberOfItemsForExpensiveSelection
    ).matches
  }

  /// Split identifiers into constituent subwords. For example "documentDownload" becomes ["document", "Download"]
  /// - Parameters:
  ///   - identifiers: Strings from the program source, like "documentDownload"
  ///   - filterLowSignalTokens: When true, removes common tokens that would falsely signal influence, like "from".
  /// - Returns: A value suitable for use with the `influencingTokenizedIdentifiers:` parameter of `selectBestMatches(…)`.
  package static func tokenize(
    influencingTokenizedIdentifiers identifiers: [String],
    filterLowSignalTokens: Bool
  ) -> [[String]] {
    identifiers.map { identifier in
      tokenize(influencingTokenizedIdentifier: identifier, filterLowSignalTokens: filterLowSignalTokens)
    }
  }

  /// Only package so that we can performance test this
  package static func performanceTest_influenceScores(
    for batches: [CandidateBatch],
    influencingTokenizedIdentifiers: [[String]],
    iterations: Int
  ) -> Double {
    let matches = batches.enumerated().flatMap { batchIndex, batch in
      (0..<batch.count).map { candidateIndex in
        Match(
          batchIndex: batchIndex,
          candidateIndex: candidateIndex,
          groupID: nil,
          score: CompletionScore(textComponent: 1, semanticComponent: 1)
        )
      }
    }
    return MatchCollator.withUnsafeMatchCollator(
      matches: matches,
      batches: batches,
      influencingTokenizedIdentifiers: influencingTokenizedIdentifiers,
      patternUTF8Length: 0,
      orderingTiesBy: { _, _ in false },
      maximumNumberOfItemsForExpensiveSelection: Self.defaultMaximumNumberOfItemsForExpensiveSelection
    ) { collator in
      return (0..<iterations).reduce(0) { accumulation, _ in
        collator.applyInfluence()
        return collator.rescoredMatches.reduce(accumulation) { accumulation, match in
          accumulation + match.individualScore.value
        }
      }
    }
  }

  package static func tokenize(
    influencingTokenizedIdentifier identifier: String,
    filterLowSignalTokens: Bool
  )
    -> [String]
  {
    var tokens: [String] = []
    identifier.withUncachedUTF8Bytes { identifierBytes in
      UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
        var tokenization = Pattern.Tokenization.allocate(
          mixedcaseBytes: identifierBytes,
          contentType: .codeCompletionSymbol,
          allocator: &allocator
        ); defer { tokenization.deallocate(allocator: &allocator) }
        tokenization.enumerate { tokenRange in
          if let token = String(bytes: identifierBytes[tokenRange], encoding: .utf8) {
            tokens.append(token)
          }
        }
      }
    }
    if filterLowSignalTokens {
      let minimumLength = 4  // Shorter tokens appear too much to be useful: (in, on, a, the…)
      let ignoredTokens: Set = ["from", "with"]
      tokens.removeAll { token in
        return (token.count < minimumLength) || ignoredTokens.contains(token.lowercased())
      }
    }
    return tokens
  }
}

extension MatchCollator {
  fileprivate struct TextIndex {
    var batch: Int
    var candidate: Int
  }
}

extension MatchCollator {
  fileprivate struct RescoredMatch {
    var originalMatchIndex: Int
    var textIndex: TextIndex
    var denseGroupID: Int?
    var individualScore: CompletionScore
    var groupScore: Double
    var falseStarts: Int
  }
}

extension MatchCollator {
  /// A wrapper to allow taking an unsafe pointer to a closure.
  fileprivate final class TieBreaker {
    var lessThan: (_ lhs: Match, _ rhs: Match) -> Bool

    init(_ lessThan: @escaping (_ lhs: Match, _ rhs: Match) -> Bool) {
      self.lessThan = lessThan
    }
  }
}

extension MatchCollator.RescoredMatch: CustomStringConvertible {
  var description: String {
    func format(_ value: Double) -> String {
      String(format: "%0.3f", value)
    }
    return
      """
      RescoredMatch(\
      idx: \(originalMatchIndex), \
      gid: \(denseGroupID?.description ?? "_"), \
      score.t: \(format(individualScore.textComponent)), \
      score.s: \(format(individualScore.semanticComponent)), \
      groupScore: \(format(groupScore)), \
      falseStarts: \(falseStarts)\
      )
      """
  }
}

fileprivate extension Pattern {
  var typedEnoughForThoroughScoring: Bool {
    patternUTF8Length >= MatchCollator.minimumPatternLengthToAlwaysRescoreWithThoroughPrecision
  }
}

// Deprecated Entry Points
extension MatchCollator {
  @available(*, deprecated, renamed: "selectBestMatches(for:from:in:influencingTokenizedIdentifiers:orderingTiesBy:)")
  package static func selectBestMatches(
    for pattern: Pattern,
    from matches: [Match],
    in batches: [CandidateBatch],
    influencingTokenizedIdentifiers: [[String]]
  ) -> [Match] {
    selectBestMatches(
      for: pattern,
      from: matches,
      in: batches,
      influencingTokenizedIdentifiers: influencingTokenizedIdentifiers,
      orderingTiesBy: { _, _ in false }
    )
  }

  @available(
    *,
    deprecated,
    message:
      "Use the MatchCollator.Selection.precision value returned from selectBestMatches(...) to choose between fast and thorough matched text ranges."
  )
  package static var bestMatchesThoroughScanningMinimumPatternLength: Int {
    minimumPatternLengthToAlwaysRescoreWithThoroughPrecision
  }
}

extension MatchCollator {
  package static let minimumPatternLengthToAlwaysRescoreWithThoroughPrecision = 2
}
