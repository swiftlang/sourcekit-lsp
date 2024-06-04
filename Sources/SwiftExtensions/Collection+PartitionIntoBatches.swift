//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public extension Collection where Index == Int {
  /// Partition the elements of the collection into `numberOfBatches` roughly equally sized batches.
  ///
  /// Elements are assigned to the batches round-robin. This ensures that elements that are close to each other in the
  /// original collection end up in different batches. This is important because eg. test files will live close to each
  /// other in the file system and test scanning wants to scan them in different batches so we don't end up with one
  /// batch only containing source files and the other only containing test files.
  func partition(intoNumberOfBatches numberOfBatches: Int) -> [[Element]] {
    var batches: [[Element]] = Array(
      repeating: {
        var batch: [Element] = []
        batch.reserveCapacity(self.count / numberOfBatches)
        return batch
      }(),
      count: numberOfBatches
    )

    for (index, element) in self.enumerated() {
      batches[index % numberOfBatches].append(element)
    }
    return batches.filter { !$0.isEmpty }
  }

  /// Partition the collection into batches that have a maximum size of `batchSize`.
  ///
  /// The last batch will contain the remainder elements.
  func partition(intoBatchesOfSize batchSize: Int) -> [[Element]] {
    var batches: [[Element]] = []
    batches.reserveCapacity(self.count / batchSize)
    var lastIndex = self.startIndex
    for index in stride(from: self.startIndex, to: self.endIndex, by: batchSize).dropFirst() + [self.endIndex] {
      batches.append(Array(self[lastIndex..<index]))
      lastIndex = index
    }
    return batches
  }
}
