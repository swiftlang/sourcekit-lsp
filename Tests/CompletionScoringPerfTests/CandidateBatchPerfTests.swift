//
//  CandidateBatchPerfTests.swift
//  CompletionScoringPerfTests
//
//  Created by Alex Hoppen on 21.2.22.
//

import CompletionScoring
import CompletionScoringTestSupport
import XCTest

class CandidateBatchPerfTests: XCTestCase {
  func testCandidateBatchCreation() {
    gaugeTiming {
      var candidateBatch = CandidateBatch()
      for _ in 1..<100_000 {
        candidateBatch.append("aAAAAAAAAAaAAAAAAAAAaAAAAAAAAA", contentType: .codeCompletionSymbol)
      }
    }
  }

  func testCandidateBatchBulkLoading() {
    typealias UTF8Bytes = Pattern.UTF8Bytes
    var randomness = RepeatableRandomNumberGenerator()
    let typeStrings = (0..<100_000).map { _ in
      SymbolGenerator.shared.randomType(using: &randomness)
    }
    let typeUTF8Buffers = typeStrings.map { typeString in
      typeString.allocateCopyOfUTF8Buffer()
    };
    defer {
      for typeUTF8Buffer in typeUTF8Buffers {
        typeUTF8Buffer.deallocate()
      }
    }

    gaugeTiming(iterations: 10) {
      drain(CandidateBatch(candidates: typeUTF8Buffers, contentType: .unknown))
    }

    // A baseline for what this method replaced, initial commit had the replacement running in 2/3rds the time of this.
    #if false
    gaugeTiming(iterations: 10) {
      var batch = CandidateBatch()
      for typeUTF8Buffer in typeUTF8Buffers {
        batch.append(typeUTF8Buffer, contentType: .unknown)
      }
      drain(batch)
    }
    #endif
  }
}
