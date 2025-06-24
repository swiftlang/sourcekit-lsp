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

package struct Timings {
  package struct Stats {
    package private(set) var min: Double
    package private(set) var max: Double
    private var total: Double
    private var count: Int

    fileprivate init(initialValue: Double) {
      total = initialValue
      min = initialValue
      max = initialValue
      count = 1
    }

    fileprivate mutating func append(_ value: Double) {
      count += 1
      total += value
      min = Swift.min(min, value)
      max = Swift.max(max, value)
    }

    var average: Double {
      total / Double(count)
    }
  }

  package private(set) var stats: Stats? = nil
  private(set) var values: [Double] = []

  package init(_ values: [Double] = []) {
    for value in values {
      append(value)
    }
  }

  private var hasVariation: Bool {
    return values.count >= 2
  }

  package var meanAverageDeviation: Double {
    if let stats = stats, hasVariation {
      var sumOfDiviations = 0.0
      for value in values {
        sumOfDiviations += abs(value - stats.average)
      }
      return sumOfDiviations / Double(values.count)
    } else {
      return 0
    }
  }

  package var standardDeviation: Double {
    if let stats = stats, hasVariation {
      var sumOfSquares = 0.0
      for value in values {
        let deviation = (value - stats.average)
        sumOfSquares += deviation * deviation
      }
      let variance = sumOfSquares / Double(values.count - 1)
      return sqrt(variance)
    } else {
      return 0
    }
  }

  package var standardError: Double {
    if hasVariation {
      return standardDeviation / sqrt(Double(values.count))
    } else {
      return 0
    }
  }

  /// There's 95% confidence that the true mean is with this distance from the sampled mean.
  var confidenceOfMean_95Percent: Double {
    if stats != nil {
      return 1.96 * standardError
    }
    return 0
  }

  @discardableResult
  mutating func append(_ value: Double) -> Stats {
    values.append(value)
    stats.mutateWrappedValue { stats in
      stats.append(value)
    }
    return stats.lazyInitialize {
      Stats(initialValue: value)
    }
  }
}

extension Optional {
  mutating func mutateWrappedValue(mutator: (inout Wrapped) -> Void) {
    if var wrapped = self {
      self = nil  // Avoid COW for clients.
      mutator(&wrapped)
      self = wrapped
    }
  }
}
