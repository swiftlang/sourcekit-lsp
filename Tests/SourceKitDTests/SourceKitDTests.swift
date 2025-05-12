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
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKTestSupport
import SourceKitD
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
import XCTest

import class TSCBasic.Process

final class SourceKitDTests: XCTestCase {
  func testMultipleNotificationHandlers() async throws {
    let sourcekitdPath = await ToolchainRegistry.forTesting.default!.sourcekitd!
    let sourcekitd = try await SourceKitD.getOrCreate(
      dylibPath: sourcekitdPath,
      pluginPaths: sourceKitPluginPaths
    )
    let keys = sourcekitd.keys
    let path = DocumentURI(for: .swift).pseudoPath

    let isExpectedNotification = { @Sendable (response: SKDResponse) -> Bool in
      if let notification: sourcekitd_api_uid_t = response.value?[keys.notification],
        let name: String = response.value?[keys.name]
      {
        return name == path && notification == sourcekitd.values.documentUpdateNotification
      }
      return false
    }

    let expectation1 = expectation(description: "handler 1")
    let handler1 = ClosureNotificationHandler { response in
      if isExpectedNotification(response) {
        expectation1.fulfill()
      }
    }
    // SourceKitD weakly references handlers
    defer {
      _fixLifetime(handler1)
    }
    await sourcekitd.addNotificationHandler(handler1)

    let expectation2 = expectation(description: "handler 2")
    let handler2 = ClosureNotificationHandler { response in
      if isExpectedNotification(response) {
        expectation2.fulfill()
      }
    }
    // SourceKitD weakly references handlers
    defer {
      _fixLifetime(handler2)
    }
    await sourcekitd.addNotificationHandler(handler2)

    let args = SKDRequestArray(sourcekitd: sourcekitd)
    if case .darwin? = Platform.current,
      let sdkpath = try? await Process.checkNonZeroExit(args: "/usr/bin/xcrun", "--show-sdk-path", "--sdk", "macosx")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    {
      args += ["-sdk", sdkpath]
    }
    args.append(path)

    let req = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.editorOpen,
      keys.name: path,
      keys.sourceText: """
      func foo() {}
      """,
      keys.compilerArgs: args,
    ])

    _ = try await sourcekitd.send(req, timeout: defaultTimeoutDuration, fileContents: nil)

    try await fulfillmentOfOrThrow(expectation1, expectation2)

    let close = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.editorClose,
      keys.name: path,
    ])
    _ = try await sourcekitd.send(close, timeout: defaultTimeoutDuration, fileContents: nil)
  }
}

private final class ClosureNotificationHandler: SKDNotificationHandler {
  let f: @Sendable (SKDResponse) -> Void

  init(_ f: @Sendable @escaping (SKDResponse) -> Void) {
    self.f = f
  }

  func notification(_ response: SKDResponse) {
    f(response)
  }
}
