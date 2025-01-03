//
//  ScoringPerfTests.swift
//  CompletionScoringPerfTests
//
//  Created by Ben Langmuir on 1/25/21.
//

import CompletionScoring
import CompletionScoringTestSupport
import XCTest

typealias Pattern = CompletionScoring.Pattern

class ScoringPerfTests: XCTestCase {
  #if DEBUG
  static let scale = 1
  #else
  static let scale = 100
  #endif
  var scale: Int { Self.scale }

  private enum Scenario {
    case fastScoringOnly
    case fullScoringAndCutoff
    case fullScoringAndCutoffWithInfluencers
    case fullScoringAndCutoffWithInfluencersAndSingleLetterFilter
    case fullScoringAndCutoffWithoutInfluencersAndSingleLetterFilter

    var selectBest: Bool {
      switch self {
      case .fastScoringOnly: return false
      case .fullScoringAndCutoff: return true
      case .fullScoringAndCutoffWithInfluencers: return true
      case .fullScoringAndCutoffWithInfluencersAndSingleLetterFilter: return true
      case .fullScoringAndCutoffWithoutInfluencersAndSingleLetterFilter: return true
      }
    }

    var usesInfluencers: Bool {
      switch self {
      case .fastScoringOnly: return false
      case .fullScoringAndCutoff: return false
      case .fullScoringAndCutoffWithInfluencers: return true
      case .fullScoringAndCutoffWithInfluencersAndSingleLetterFilter: return true
      case .fullScoringAndCutoffWithoutInfluencersAndSingleLetterFilter: return true
      }
    }

    var patternPrefixLengths: Range<Int> {
      switch self {
      case .fastScoringOnly: return 0..<16
      case .fullScoringAndCutoff: return 0..<16
      case .fullScoringAndCutoffWithInfluencers: return 0..<16
      case .fullScoringAndCutoffWithInfluencersAndSingleLetterFilter: return 1..<2
      case .fullScoringAndCutoffWithoutInfluencersAndSingleLetterFilter: return 1..<2
      }
    }
  }

  func testFastConcurrentScoringPerformance() throws {
    testConcurrentScoringAndBatchingPerformance(scenario: .fastScoringOnly)
  }

  func testFullScoringAndSelectionPerformanceWithoutInfluencers() throws {
    testConcurrentScoringAndBatchingPerformance(scenario: .fullScoringAndCutoff)
  }

  func testFullScoringAndSelectionPerformanceWithInfluencers() throws {
    testConcurrentScoringAndBatchingPerformance(scenario: .fullScoringAndCutoffWithInfluencers)
  }

  func testFullScoringAndSelectionPerformanceWithInfluencersAndSingleLetterFilter() throws {
    testConcurrentScoringAndBatchingPerformance(scenario: .fullScoringAndCutoffWithInfluencersAndSingleLetterFilter)
  }

  func testFullScoringAndSelectionPerformanceWithoutInfluencersAndSingleLetterFilter() throws {
    testConcurrentScoringAndBatchingPerformance(
      scenario: .fullScoringAndCutoffWithoutInfluencersAndSingleLetterFilter
    )
  }

  private func testConcurrentScoringAndBatchingPerformance(scenario: Scenario) {
    let corpus = Corpus(patternPrefixLengths: scenario.patternPrefixLengths)
    let batches = corpus.batches
    let totalCandidates = corpus.totalCandidates
    let sessions: [[Pattern]] = {
      var patternGroups: [[Pattern]] = []
      for pattern in corpus.patterns {
        if let previous = patternGroups.last?.last, pattern.text.hasPrefix(previous.text) {
          patternGroups[patternGroups.count - 1].append(pattern)
        } else {
          patternGroups.append([pattern])
        }
      }
      return patternGroups
    }()

    var scoredCandidates = 0
    var matchedCandidates = 0
    var selectedCandidates = 0
    var attempts = 0
    let tokenizedInfluencers = scenario.usesInfluencers ? corpus.tokenizedInfluencers : []
    gaugeTiming {
      for session in sessions {
        let selector = ScoredMatchSelector(batches: batches)
        for pattern in session {
          let matches = selector.scoredMatches(pattern: pattern, precision: .fast)
          if scenario.selectBest {
            let fastMatchReps: [MatchCollator.Match] = matches.map { match in
              let candidate = corpus.providers[match.batchIndex].candidates[match.candidateIndex]
              let score = CompletionScore(
                textComponent: match.textScore,
                semanticComponent: candidate.semanticClassification.score
              )
              return MatchCollator.Match(
                batchIndex: match.batchIndex,
                candidateIndex: match.candidateIndex,
                groupID: candidate.groupID,
                score: score
              )
            }
            let bestMatches = MatchCollator.selectBestMatches(
              for: pattern,
              from: fastMatchReps,
              in: batches,
              influencingTokenizedIdentifiers: tokenizedInfluencers
            ) { lhs, rhs in
              let lhsCandidate = corpus.providers[lhs.batchIndex].candidates[lhs.candidateIndex]
              let rhsCandidate = corpus.providers[rhs.batchIndex].candidates[rhs.candidateIndex]
              return lhsCandidate.displayText < rhsCandidate.displayText
            }
            selectedCandidates += bestMatches.count
          }
          matchedCandidates += matches.count
          scoredCandidates += totalCandidates
          attempts += 1
        }
      }
    }
    print("> Sessions: \(sessions.map {$0.map(\.text)})")
    print("> Candidates: \(scoredCandidates)")
    print("> Matches: \(matchedCandidates)")
    print("> Selected: \(selectedCandidates)")
    print("> Attempts: \(attempts)")
  }

  func testThoroughConcurrentScoringPerformance() throws {
    let corpus = Corpus(
      patternPrefixLengths: MatchCollator.minimumPatternLengthToAlwaysRescoreWithThoroughPrecision..<16
    )
    let batches = corpus.batches

    struct MatchSet {
      var pattern: Pattern
      var fastMatchReps: [MatchCollator.Match]
    }

    let matchSets: [MatchSet] = corpus.patterns.map { pattern in
      let matches = pattern.scoredMatches(across: batches, precision: .fast)
      let fastMatchReps = matches.map { match in
        let candidate = corpus.providers[match.batchIndex].candidates[match.candidateIndex]
        let score = CompletionScore(
          textComponent: match.textScore,
          semanticComponent: candidate.semanticClassification.score
        )
        return MatchCollator.Match(
          batchIndex: match.batchIndex,
          candidateIndex: match.candidateIndex,
          groupID: candidate.groupID,
          score: score
        )
      }
      return MatchSet(pattern: pattern, fastMatchReps: fastMatchReps)
    }
    gaugeTiming {
      for matchSet in matchSets {
        let bestMatches = MatchCollator.selectBestMatches(
          for: matchSet.pattern,
          from: matchSet.fastMatchReps,
          in: batches,
          influencingTokenizedIdentifiers: []
        ) { lhs, rhs in
          return false
        }
        drain(bestMatches)
      }
    }
  }

  func testInfluencingIdentifiersInIsolation() {
    let corpus = Corpus(patternPrefixLengths: Scenario.fullScoringAndCutoffWithInfluencers.patternPrefixLengths)
    gaugeTiming {
      drain(
        MatchCollator.performanceTest_influenceScores(
          for: corpus.batches,
          influencingTokenizedIdentifiers: corpus.tokenizedInfluencers,
          iterations: 350
        )
      )
    }
  }

  func testTokenizingInIsolation() {
    let corpus = Corpus(patternPrefixLengths: Scenario.fullScoringAndCutoffWithInfluencers.patternPrefixLengths)
    gaugeTiming {
      for pattern in corpus.patterns {
        for batch in corpus.batches {
          drain(pattern.testPerformance_tokenizing(batch: batch, contentType: .codeCompletionSymbol))
        }
      }
    }
  }
}
