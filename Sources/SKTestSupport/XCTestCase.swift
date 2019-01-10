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

public extension XCTestCase {

#if os(macOS)
  func wait<T>(for condition: @escaping (T) -> Bool, object: T, timeout: TimeInterval = 5) -> Bool {
    let change = XCTNSPredicateExpectation(predicate: NSPredicate(block: { (object, _) in condition(object as! T) }), object: object)
    let result = XCTWaiter.wait(for: [change], timeout: timeout)
    return result == .completed
  }
#endif

}
