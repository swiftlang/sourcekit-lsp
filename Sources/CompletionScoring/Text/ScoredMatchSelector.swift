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

/// Use `ScoredMatchSelector` to find the matching indexes for a `Pattern` from an array of `CandidateBatch` structures.
/// It's a reference type to allow sharing state between calls to improve performance, and has an internal lock,
/// so only enter it from one thread at a time.
///
/// It's primary performance improvement is that it creates and initializes all of the scratch buffers ahead of time, so that they can be
/// amortized across all matching calls.
package class ScoredMatchSelector {
  typealias CandidateBatchSlice = Pattern.ScoringWorkload.CandidateBatchSlice
  typealias CandidateBatchesMatch = Pattern.CandidateBatchesMatch
  typealias ScoringWorkload = Pattern.ScoringWorkload

  private let threadWorkloads: [ThreadWorkload]
  private let queue: DispatchQueue
  package init(batches: [CandidateBatch]) {
    let scoringWorkloads = ScoringWorkload.workloads(
      for: batches,
      parallelism: ProcessInfo.processInfo.activeProcessorCount
    )
    threadWorkloads = scoringWorkloads.map { scoringWorkload in
      ThreadWorkload(allBatches: batches, slices: scoringWorkload.slices)
    }
    queue = DispatchQueue(label: "ScoredMatchSelector")
  }

  /// Find all of the matches across `batches` and score them, returning the scored results. This is a first part of selecting matches. Later the matches will be combined with matches from other providers, where we'll pick the best matches and sort them with `selectBestMatches(from:textProvider:)`
  package func scoredMatches(pattern: Pattern, precision: Pattern.Precision) -> [Pattern.CandidateBatchesMatch] {
    /// The whole point is share the allocation space across many re-uses, but if the client calls into us concurrently, we shouldn't just crash. An assert would also be acceptable.
    return queue.sync {
      // `nonisolated(unsafe)` is fine because every concurrent iteration accesses a different element.
      nonisolated(unsafe) let threadWorkloads = threadWorkloads
      DispatchQueue.concurrentPerform(iterations: threadWorkloads.count) { index in
        threadWorkloads[index].updateOutput(pattern: pattern, precision: precision)
      }
      let totalMatchCount = threadWorkloads.sum { threadWorkload in
        threadWorkload.matchCount
      }
      return Array(unsafeUninitializedCapacity: totalMatchCount) { aggregate, initializedCount in
        if var writePosition = aggregate.baseAddress {
          for threadWorkload in threadWorkloads {
            threadWorkload.moveResults(to: &writePosition)
          }
        } else {
          precondition(totalMatchCount == 0)
        }
        initializedCount = totalMatchCount
      }
    }
  }
}

extension ScoredMatchSelector {
  fileprivate final class ThreadWorkload {

    fileprivate private(set) var matchCount = 0
    private let output: UnsafeMutablePointer<CandidateBatchesMatch>
    private let slices: [CandidateBatchSlice]
    private let allBatches: [CandidateBatch]

    init(allBatches: [CandidateBatch], slices: [CandidateBatchSlice]) {
      let candidateCount = slices.sum { slice in
        slice.candidateRange.count
      }
      self.output = UnsafeMutablePointer.allocate(capacity: candidateCount)
      self.slices = slices
      self.allBatches = allBatches
    }

    deinit {
      precondition(matchCount == 0)  // Missing call to moveResults?
      output.deallocate()
    }

    fileprivate func updateOutput(pattern: Pattern, precision: Pattern.Precision) {
      precondition(matchCount == 0)  // Missing call to moveResults?
      self.matchCount = UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
        var matchCount = 0
        for slice in slices {
          let batch = allBatches[slice.batchIndex]
          batch.enumerate(slice.candidateRange) { candidateIndex, candidate in
            if let score = pattern.matchAndScore(
              candidate: candidate,
              precision: precision,
              allocator: &allocator
            ) {
              let match = CandidateBatchesMatch(
                batchIndex: slice.batchIndex,
                candidateIndex: candidateIndex,
                textScore: score.value
              )
              output.advanced(by: matchCount).initialize(to: match)
              matchCount += 1
            }
          }
        }
        return matchCount
      }
    }

    fileprivate func moveResults(to aggregate: inout UnsafeMutablePointer<CandidateBatchesMatch>) {
      aggregate.moveInitialize(from: output, count: matchCount)
      aggregate = aggregate.advanced(by: matchCount)
      matchCount = 0
    }
  }
}
