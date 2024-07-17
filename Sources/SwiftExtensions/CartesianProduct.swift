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

/// Calculates the cartesian product of `lhs` and `rhs`
///
/// Creates an array of tuple pairs, known as "Cartesian Product", which contains all the possible ways of
/// pairing each element from `lhs` with each element in `rhs`.
///
/// Example Usage:
/// ```swift
/// let alphaNumberPairs = cartesianProduct([1, 2, 3],  ["a", "b", "c"])
/// print(alphaNumberPairs)
/// // Prints: "[(1, "a"), (2, "a"), (3, "a"), (1, "b"), (2, "b"), (3, "b"), (1, "c"), (2, "c"), (3, "c")]"
/// ```
package func cartesianProduct<T, U>(_ lhs: [T], _ rhs: [U]) -> [(T, U)] {
  var result: [(T, U)] = []

  for lhsElement in lhs {
    for rhsElement in rhs {
      result.append((lhsElement, rhsElement))
    }
  }
  return result
}
