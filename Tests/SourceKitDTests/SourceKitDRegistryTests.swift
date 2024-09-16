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

import SKSupport
import SKTestSupport
import SourceKitD
import SwiftExtensions
import TSCBasic
import XCTest

final class SourceKitDRegistryTests: XCTestCase {

  func testAdd() async throws {
    let registry = SourceKitDRegistry()

    let a = try await FakeSourceKitD.getOrCreate(AbsolutePath(validating: "/a"), in: registry)
    let b = try await FakeSourceKitD.getOrCreate(AbsolutePath(validating: "/b"), in: registry)
    let a2 = try await FakeSourceKitD.getOrCreate(AbsolutePath(validating: "/a"), in: registry)

    XCTAssert(a === a2)
    XCTAssert(a !== b)
  }

  func testRemove() async throws {
    let registry = SourceKitDRegistry()

    let a = await FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry)
    await assertTrue(registry.remove(try AbsolutePath(validating: "/a")) === a)
    await assertNil(registry.remove(try AbsolutePath(validating: "/a")))
  }

  func testRemoveResurrect() async throws {
    let registry = SourceKitDRegistry()

    @inline(never)
    func scope(registry: SourceKitDRegistry) async throws -> UInt32 {
      let a = await FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry)

      await assertTrue(a === FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry))
      await assertTrue(registry.remove(try AbsolutePath(validating: "/a")) === a)
      // Resurrected.
      await assertTrue(a === FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry))
      // Remove again.
      await assertTrue(registry.remove(try AbsolutePath(validating: "/a")) === a)
      return (a as! FakeSourceKitD).token
    }

    let id = try await scope(registry: registry)
    let a2 = await FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry)
    XCTAssertNotEqual(id, (a2 as! FakeSourceKitD).token)
  }
}

private let nextToken = AtomicUInt32(initialValue: 0)

final class FakeSourceKitD: SourceKitD {
  let token: UInt32
  var api: sourcekitd_api_functions_t { fatalError() }
  var keys: sourcekitd_api_keys { fatalError() }
  var requests: sourcekitd_api_requests { fatalError() }
  var values: sourcekitd_api_values { fatalError() }
  func addNotificationHandler(_ handler: SKDNotificationHandler) { fatalError() }
  func removeNotificationHandler(_ handler: SKDNotificationHandler) { fatalError() }
  private init() {
    token = nextToken.fetchAndIncrement()
  }

  static func getOrCreate(_ path: AbsolutePath, in registry: SourceKitDRegistry) async -> SourceKitD {
    return await registry.getOrAdd(path, create: { Self.init() })
  }

  package func log(request: SKDRequestDictionary) {}
  package func log(response: SKDResponse) {}
  package func log(crashedRequest: SKDRequestDictionary, fileContents: String?) {}
  package func logRequestCancellation(request: SKDRequestDictionary) {}
}
