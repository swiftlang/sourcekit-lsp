//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

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
    }
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
