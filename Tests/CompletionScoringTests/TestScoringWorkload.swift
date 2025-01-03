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
import CompletionScoringTestSupport
import XCTest

/// This class verifies that the work slicing used in concurrent matching distributes the work items
/// across threads in the expected ways.
///
/// The most essential requirement is that it chooses exactly one work unit for every Candidate in the CandidateBatches.
///
/// The next requirement is that it distributes the work in a way that maximizes memory locality.
///
/// Each test has a comment like "AAB / 3 = A, A, B". Each unique letter represents a candidate block, and the
/// repetitions of that letter indicate how many candidates are in that block. So here there is a block with two
/// candidates, and another block with 1 candidate. If we distribute that to three workers, we expect each one to get
/// 1 candidate: A, A, B.
///
/// The tests test all division of 0...N candidates across 1...N+1 workers, where N is 3.
class TestScoringWorkload: XCTestCase {
  func workloads(for batchSizes: [Int], parallelism: Int) -> [Pattern.ScoringWorkload] {
    let batches = batchSizes.map { batchSize in
      CandidateBatch(symbols: Array(repeating: " ", count: batchSize))
    }
    return Pattern.ScoringWorkload.workloads(for: batches, parallelism: parallelism)
  }

  func expect(batches: [Int], parallelism: Int, produces: [Pattern.ScoringWorkload]) {
    XCTAssertEqual(workloads(for: batches, parallelism: parallelism), produces, "Slicing \(batches)")
  }

  /// Shorthand for making slices
  func Workload(outputAt: Int, _ units: [Pattern.ScoringWorkload.CandidateBatchSlice]) -> Pattern.ScoringWorkload {
    Pattern.ScoringWorkload(outputStartIndex: outputAt, slices: units)
  }

  /// Shorthand for making slice units
  func Slice(batch: Int, candidates: Range<Int>) -> Pattern.ScoringWorkload.CandidateBatchSlice {
    return Pattern.ScoringWorkload.CandidateBatchSlice(batchIndex: batch, candidateRange: candidates)
  }

  func testLeadingAndTrailingZerosHaveNoImpact() {
    // Look for division by zero, never terminating etc with empty cases.
    for cores in 1..<3 {
      expect(batches: [], parallelism: cores, produces: [])
      expect(batches: [0], parallelism: cores, produces: [])
      expect(batches: [0, 0], parallelism: cores, produces: [])

      expect(
        batches: [1],
        parallelism: cores,
        produces: [
          Workload(outputAt: 0, [Slice(batch: 0, candidates: 0..<1)])
        ]
      )
      expect(
        batches: [1, 0],
        parallelism: cores,
        produces: [
          Workload(outputAt: 0, [Slice(batch: 0, candidates: 0..<1)])
        ]
      )
      expect(
        batches: [0, 1],
        parallelism: cores,
        produces: [
          Workload(outputAt: 0, [Slice(batch: 1, candidates: 0..<1)])
        ]
      )
    }
  }

  func testDivisionsOf2Candidates() throws {
    // AA / 1 = AA
    expect(
      batches: [2],
      parallelism: 1,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 2)])
      ]
    )

    // AA / 2 = A, A
    expect(
      batches: [2],
      parallelism: 2,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(outputAt: 1, [Slice(batch: 0, candidates: 1 ..+ 1)]),
      ]
    )

    // AA / 3 = AA
    expect(
      batches: [2],
      parallelism: 3,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 2)])
      ]
    )

    // AB / 1 = AB
    expect(
      batches: [1, 1],
      parallelism: 1,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1),
            Slice(batch: 1, candidates: 0 ..+ 1),
          ]
        )
      ]
    )

    // AB / 2 = A, B
    expect(
      batches: [1, 1],
      parallelism: 2,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(outputAt: 1, [Slice(batch: 1, candidates: 0 ..+ 1)]),
      ]
    )

    // AB / 3 = AB
    expect(
      batches: [1, 1],
      parallelism: 3,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1),
            Slice(batch: 1, candidates: 0 ..+ 1),
          ]
        )
      ]
    )
  }

  func testDivisonsOf3Candidates() {
    // AAA / 1 = AAA
    expect(
      batches: [3],
      parallelism: 1,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 3)])
      ]
    )

    // AAA / 2 = A, AA
    expect(
      batches: [3],
      parallelism: 2,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(outputAt: 1, [Slice(batch: 0, candidates: 1 ..+ 2)]),
      ]
    )

    // AAA / 3 = A, A, A
    expect(
      batches: [3],
      parallelism: 3,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(outputAt: 1, [Slice(batch: 0, candidates: 1 ..+ 1)]),
        Workload(outputAt: 2, [Slice(batch: 0, candidates: 2 ..+ 1)]),
      ]
    )

    // AAA / 4 = AAA
    expect(
      batches: [3],
      parallelism: 4,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 3)])
      ]
    )

    // ABB / 1 = ABB
    expect(
      batches: [1, 2],
      parallelism: 1,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1),
            Slice(batch: 1, candidates: 0 ..+ 2),
          ]
        )
      ]
    )

    // ABB / 2 = A, BB
    expect(
      batches: [1, 2],
      parallelism: 2,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(outputAt: 1, [Slice(batch: 1, candidates: 0 ..+ 2)]),
      ]
    )

    // ABB / 3 = A, B, B
    expect(
      batches: [1, 2],
      parallelism: 3,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(outputAt: 1, [Slice(batch: 1, candidates: 0 ..+ 1)]),
        Workload(outputAt: 2, [Slice(batch: 1, candidates: 1 ..+ 1)]),
      ]
    )

    // ABB / 4 = ABB
    expect(
      batches: [1, 2],
      parallelism: 4,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1),
            Slice(batch: 1, candidates: 0 ..+ 2),
          ]
        )
      ]
    )

    // AAB / 1 = AAB
    expect(
      batches: [2, 1],
      parallelism: 1,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 2),
            Slice(batch: 1, candidates: 0 ..+ 1),
          ]
        )
      ]
    )

    // AAB / 2 = A, AB
    expect(
      batches: [2, 1],
      parallelism: 2,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(
          outputAt: 1,
          [
            Slice(batch: 0, candidates: 1 ..+ 1),
            Slice(batch: 1, candidates: 0 ..+ 1),
          ]
        ),
      ]
    )

    // AAB / 3 = A, A, B
    expect(
      batches: [2, 1],
      parallelism: 3,
      produces: [
        Workload(outputAt: 0, [Slice(batch: 0, candidates: 0 ..+ 1)]),
        Workload(outputAt: 1, [Slice(batch: 0, candidates: 1 ..+ 1)]),
        Workload(outputAt: 2, [Slice(batch: 1, candidates: 0 ..+ 1)]),
      ]
    )

    // AAB / 4 = AAB
    expect(
      batches: [2, 1],
      parallelism: 4,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 2),
            Slice(batch: 1, candidates: 0 ..+ 1),
          ]
        )
      ]
    )

    // ABC / 1 = ABC
    expect(
      batches: [1, 1, 1],
      parallelism: 1,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1),
            Slice(batch: 1, candidates: 0 ..+ 1),
            Slice(batch: 2, candidates: 0 ..+ 1),
          ]
        )
      ]
    )

    // ABC / 2 = A, BC
    expect(
      batches: [1, 1, 1],
      parallelism: 2,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1)
          ]
        ),
        Workload(
          outputAt: 1,
          [
            Slice(batch: 1, candidates: 0 ..+ 1),
            Slice(batch: 2, candidates: 0 ..+ 1),
          ]
        ),
      ]
    )

    // ABC / 3 = A, BC
    expect(
      batches: [1, 1, 1],
      parallelism: 3,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1)
          ]
        ),
        Workload(
          outputAt: 1,
          [
            Slice(batch: 1, candidates: 0 ..+ 1)
          ]
        ),
        Workload(
          outputAt: 2,
          [
            Slice(batch: 2, candidates: 0 ..+ 1)
          ]
        ),
      ]
    )

    // ABC / 4 = ABC
    expect(
      batches: [1, 1, 1],
      parallelism: 4,
      produces: [
        Workload(
          outputAt: 0,
          [
            Slice(batch: 0, candidates: 0 ..+ 1),
            Slice(batch: 1, candidates: 0 ..+ 1),
            Slice(batch: 2, candidates: 0 ..+ 1),
          ]
        )
      ]
    )
  }
}
