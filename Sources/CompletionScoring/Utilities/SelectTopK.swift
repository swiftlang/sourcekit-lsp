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

extension UnsafeMutableBufferPointer {
  /// Find the top `k` elements as ordered by `lessThan`, and move them to the front of the receiver.
  /// The order of elements at positions `k..<count` is undefined.
  ///
  /// Uses a partial heap sort to run in O(k * log(n)) time.
  package mutating func selectTopKAndTruncate(_ k: Int, lessThan: (Element, Element) -> Bool) {
    if k < count {
      withoutActuallyEscaping(lessThan) { lessThan in
        var sorter = HeapSorter(self, orderedBy: lessThan)
        sorter.sortToBack(maxSteps: k)
        let slide = count - k
        for frontIdx in 0..<k {
          let backIdx = frontIdx + slide
          self[frontIdx] = self[backIdx]
        }
      }
      self.truncateAndDeinitializeTail(maxLength: k)
    }
  }
}

private struct HeapSorter<Element> {
  var heapStorage: UnsafeMutablePointer<Element>
  var heapCount: Int
  var inOrder: (Element, Element) -> Bool

  init(_ storage: UnsafeMutableBufferPointer<Element>, orderedBy lessThan: @escaping (Element, Element) -> Bool) {
    self.heapCount = storage.count
    self.heapStorage = storage.baseAddress!

    self.inOrder = { lhs, rhs in  // Make a `<=` out of `<`, we don't need to push down when equal
      return lessThan(lhs, rhs) || !lessThan(rhs, lhs)
    }
    if heapCount > 0 {
      let lastIndex = heapLastIndex
      let lastItemOnSecondLevelFromBottom = lastIndex.parent
      for index in (0...lastItemOnSecondLevelFromBottom.value).reversed() {
        pushParentDownIfNeeded(at: HeapIndex(index))
      }
    }
  }

  struct HeapIndex: Comparable {
    var value: Int

    init(_ value: Int) {
      self.value = value
    }

    var parent: Self { .init((value - 1) / 2) }
    var leftChild: Self { .init((value * 2) + 1) }
    var rightChild: Self { .init((value * 2) + 2) }

    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.value < rhs.value
    }
  }

  var heapStartIndex: HeapIndex { .init(0) }
  var heapLastIndex: HeapIndex { .init(heapCount - 1) }
  var heapEndIndex: HeapIndex { .init(heapCount) }

  subscript(heapIndex heapIndex: HeapIndex) -> Element {
    get {
      heapStorage[heapIndex.value]
    }
    set {
      heapStorage[heapIndex.value] = newValue
    }
  }

  func heapSwap(_ a: HeapIndex, _ b: HeapIndex) {
    let t = heapStorage[a.value]
    heapStorage[a.value] = heapStorage[b.value]
    heapStorage[b.value] = t
  }

  mutating func sortToBack(maxSteps: Int) {
    precondition(maxSteps < heapCount)
    for _ in 0..<maxSteps {
      heapSwap(heapStartIndex, heapLastIndex)
      heapCount -= 1
      pushParentDownIfNeeded(at: heapStartIndex)
    }
  }

  mutating func pushParentDownIfNeeded(at parent: HeapIndex) {
    var promoted = parent
    if parent.leftChild < heapEndIndex && !inOrder(self[heapIndex: promoted], self[heapIndex: parent.leftChild]) {
      promoted = parent.leftChild
    }
    if parent.rightChild < heapEndIndex && !inOrder(self[heapIndex: promoted], self[heapIndex: parent.rightChild]) {
      promoted = parent.rightChild
    }
    if promoted != parent {
      heapSwap(parent, promoted)
      pushParentDownIfNeeded(at: promoted)
    }
  }

  func verifyInvariants() throws {
    func verifyAndContinue(parent: HeapIndex, child: HeapIndex) throws {
      if child < heapEndIndex {
        if !inOrder(self[heapIndex: parent], self[heapIndex: child]) {
          throw GenericError(
            "\(self[heapIndex: parent]) is out of order with respect to \(self[heapIndex: child])"
          )
        }
        try check(child)
      }
    }
    func check(_ parent: HeapIndex) throws {
      try verifyAndContinue(parent: parent, child: parent.leftChild)
      try verifyAndContinue(parent: parent, child: parent.rightChild)
    }
    if heapCount > 0 {
      try check(heapStartIndex)
    }
  }
}
