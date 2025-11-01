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

import Csourcekitd
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
import SKTestSupport
import SourceKitD
import SwiftExtensions
import TSCBasic
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

final class SourceKitDRegistryTests: SourceKitLSPTestCase {

  func testAdd() async throws {
    let registry = SourceKitDRegistry<FakeSourceKitD>()

    let a = await FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/a"), in: registry)
    let b = await FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/b"), in: registry)
    let a2 = await FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/a"), in: registry)

    XCTAssert(a === a2)
    XCTAssert(a !== b)
  }

  func testRemove() async throws {
    let registry = SourceKitDRegistry<FakeSourceKitD>()

    let a = await FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/a"), in: registry)
    await assertTrue(registry.remove(URL(fileURLWithPath: "/a")) === a)
    await assertNil(registry.remove(URL(fileURLWithPath: "/a")))
  }

  func testRemoveResurrect() async throws {
    let registry = SourceKitDRegistry<FakeSourceKitD>()

    @inline(never)
    func scope(registry: SourceKitDRegistry<FakeSourceKitD>) async throws -> UInt32 {
      let a = await FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/a"), in: registry)

      await assertTrue(a === FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/a"), in: registry))
      await assertTrue(registry.remove(URL(fileURLWithPath: "/a")) === a)
      // Resurrected.
      await assertTrue(a === FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/a"), in: registry))
      // Remove again.
      await assertTrue(registry.remove(URL(fileURLWithPath: "/a")) === a)
      return a.token
    }

    let id = try await scope(registry: registry)
    let a2 = await FakeSourceKitD.getOrCreate(URL(fileURLWithPath: "/a"), in: registry)
    XCTAssertNotEqual(id, a2.token)
  }
}

private let nextToken = AtomicUInt32(initialValue: 0)

final class FakeSourceKitD: Sendable {
  let token: UInt32

  private init() {
    token = nextToken.fetchAndIncrement()
  }

  static func getOrCreate(_ url: URL, in registry: SourceKitDRegistry<FakeSourceKitD>) async -> FakeSourceKitD {
    return await registry.getOrAdd(url, pluginPaths: nil, create: { Self.init() })
  }
}
