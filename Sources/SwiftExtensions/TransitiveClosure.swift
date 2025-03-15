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

package func transitiveClosure<T: Hashable>(of values: some Collection<T>, successors: (T) -> Set<T>) -> Set<T> {
  var transitiveClosure: Set<T> = []
  var workList = Array(values)
  while let element = workList.popLast() {
    for successor in successors(element) {
      if transitiveClosure.insert(successor).inserted {
        workList.append(successor)
      }
    }
  }
  return transitiveClosure
}
