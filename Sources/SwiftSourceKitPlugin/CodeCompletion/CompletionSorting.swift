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

struct CompletionSorting {
  private let session: CompletionSession
  // private let items: [ASTCompletionItem]
  // private let filterCandidates: CandidateBatch
  private let pattern: Pattern

  struct Match {
    let score: CompletionScore
    let index: Int
  }

  init(
    filterText: String,
    in session: CompletionSession
  ) {
    self.session = session
    self.pattern = Pattern(text: filterText)
  }

  /// Invoke `callback` with the top `maxResults` results and their scores
  /// The buffer passed to `callback` is only valid for the duration of `callback`.
  /// Returns the return value of `callback`.
  func withScoredAndFilter<T>(maxResults: Int, _ callback: (UnsafeBufferPointer<Match>) -> T) -> T {
    var matches: UnsafeMutableBufferPointer<Match>
    defer { matches.deinitializeAllAndDeallocate() }
    if pattern.text.isEmpty {
      matches = .allocate(capacity: session.items.count)
      for (index, item) in session.items.enumerated() {
        matches.initialize(
          index: index,
          to: Match(
            score: CompletionScore(textComponent: 1, semanticComponent: item.semanticScore(in: session)),
            index: index
          )
        )
      }
    } else {
      let candidateMatches = pattern.scoredMatches(in: session.filterCandidates, precision: .fast)
      matches = .allocate(capacity: candidateMatches.count)
      for (index, match) in candidateMatches.enumerated() {
        let semanticScore = session.items[match.candidateIndex].semanticScore(in: session)
        matches.initialize(
          index: index,
          to: Match(
            score: CompletionScore(textComponent: match.textScore, semanticComponent: semanticScore),
            index: match.candidateIndex
          )
        )
      }
    }

    "".withCString { emptyCString in
      matches.selectTopKAndTruncate(min(maxResults, matches.count)) {
        if $0.score != $1.score {
          return $0.score > $1.score
        } else {
          // Secondary sort by name. This is important to do early since when the
          // filter text is empty there will be many tied scores and we do not
          // want non-deterministic results in top-level completions.
          let lhs = session.items[$0.index].filterNameCString ?? emptyCString
          let rhs = session.items[$1.index].filterNameCString ?? emptyCString
          return strcmp(lhs, rhs) < 0
        }
      }
    }

    return callback(UnsafeBufferPointer(matches))
  }
}
