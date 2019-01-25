//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import SKTestSupport
@testable import SKSupport

class CollectionPerfTests: PerfTestCase {

  let collection: [UInt8] = [UInt8]("""
    Random-access collections can move indices any distance and measure the distance between indices in O(1) time.
    Therefore, the fundamental difference between random-access and bidirectional collections is that operations
    that depend on index movement or distance measurement offer significantly improved efficiency. For example, a
    random-access collection’s count property is calculated in O(1) instead of requiring iteration of an
    entire collection. Conforming to the RandomAccessCollection Protocol: the RandomAccessCollection protocol adds
    further constraints on the associated Indices and SubSequence types, but otherwise imposes no additional
    requirements over the BidirectionalCollection protocol. However, in order to meet the complexity guarantees of
    a random-access collection, either the index for your custom type must conform to the Strideable protocol or
    you must implement the index(_:offsetBy:) and distance(from:to:) methods with O(1 efficiency.
    """.utf8)

  func testFirstIndexWithShortestPattern() {
    let keyword: [UInt8] = [UInt8](".".utf8)
    self.measure {
      _ = collection.firstIndex(of: keyword)
    }
  }

  func testFirstIndexWithShortPattern() {
    let keyword: [UInt8] = [UInt8]("(1)".utf8)
    self.measure {
      _ = collection.firstIndex(of: keyword)
    }
  }

  func testFirstIndexWithMidRangePattern() {
    let keyword: [UInt8] = [UInt8]("collection".utf8)
    self.measure {
      _ = collection.firstIndex(of: keyword)
    }
  }

  func testFirstIndexWithSecondMidRangePattern() {
    let keyword: [UInt8] = [UInt8]("the RandomAccessCollection".utf8)
    self.measure {
      _ = collection.firstIndex(of: keyword)
    }
  }

  func testFirstIndexWithLongPattern() {
    let keyword: [UInt8] = [UInt8]("For example, a random-access collection’s count property is calculated in O(1) instead of requiring iteration of an entire collection.".utf8)
    self.measure {
      _ = collection.firstIndex(of: keyword)
    }
  }
}
