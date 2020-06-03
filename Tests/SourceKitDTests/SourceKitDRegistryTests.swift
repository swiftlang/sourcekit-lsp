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

import SourceKitD
import TSCBasic
import XCTest

final class SourceKitDRegistryTests: XCTestCase {

  func testAdd() {
    let registry = SourceKitDRegistry()

    let a = FakeSourceKitD.getOrCreate(AbsolutePath("/a"), in: registry)
    let b = FakeSourceKitD.getOrCreate(AbsolutePath("/b"), in: registry)
    let a2 = FakeSourceKitD.getOrCreate(AbsolutePath("/a"), in: registry)

    XCTAssert(a === a2)
    XCTAssert(a !== b)
  }

  func testRemove() {
    let registry = SourceKitDRegistry()

    let a = FakeSourceKitD.getOrCreate(AbsolutePath("/a"), in: registry)
    XCTAssert(registry.remove(AbsolutePath("/a")) === a)
    XCTAssertNil(registry.remove(AbsolutePath("/a")))
  }

  func testRemoveResurrect() {
    let registry = SourceKitDRegistry()

    @inline(never)
    func scope(registry: SourceKitDRegistry) -> Int {
      let a = FakeSourceKitD.getOrCreate(AbsolutePath("/a"), in: registry)

      XCTAssert(a === FakeSourceKitD.getOrCreate(AbsolutePath("/a"), in: registry))
      XCTAssert(registry.remove(AbsolutePath("/a")) === a)
      // Resurrected.
      XCTAssert(a === FakeSourceKitD.getOrCreate(AbsolutePath("/a"), in: registry))
      // Remove again.
      XCTAssert(registry.remove(AbsolutePath("/a")) === a)
      return (a as! FakeSourceKitD).token
    }

    let id = scope(registry: registry)
    let a2 = FakeSourceKitD.getOrCreate(AbsolutePath("/a"), in: registry)
    XCTAssertNotEqual(id, (a2 as! FakeSourceKitD).token)
  }
}

private var nextToken = 0

final class FakeSourceKitD: SourceKitD {
  let token: Int
  var api: sourcekitd_functions_t { fatalError() }
  var keys: sourcekitd_keys { fatalError() }
  var requests: sourcekitd_requests { fatalError() }
  var values: sourcekitd_values { fatalError() }
  func addNotificationHandler(_ handler: SKDNotificationHandler) { fatalError() }
  func removeNotificationHandler(_ handler: SKDNotificationHandler) { fatalError() }
  private init() {
    token = nextToken
    nextToken += 1
  }

  static func getOrCreate(_ path: AbsolutePath, in registry: SourceKitDRegistry) -> SourceKitD {
    return registry.getOrAdd(path, create: { Self.init() })
  }
}
