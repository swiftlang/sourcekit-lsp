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

import BuildServerProtocol
import BuildSystemIntegration
import Foundation
import ISDBTestSupport
import LanguageServerProtocol
import SKSupport
import SKTestSupport
import TSCBasic
import XCTest

/// The path to the INPUTS directory of shared test projects.
private let skTestSupportInputsDirectory: URL = {
  #if os(macOS)
  var resources =
    productsDirectory
    .appendingPathComponent("SourceKitLSP_SKTestSupport.bundle")
    .appendingPathComponent("Contents")
    .appendingPathComponent("Resources")
  if !FileManager.default.fileExists(atPath: resources.path) {
    // Xcode and command-line swiftpm differ about the path.
    resources.deleteLastPathComponent()
    resources.deleteLastPathComponent()
  }
  #else
  let resources = XCTestCase.productsDirectory
    .appendingPathComponent("SourceKitLSP_SKTestSupport.resources")
  #endif
  guard FileManager.default.fileExists(atPath: resources.path) else {
    fatalError("missing resources \(resources.path)")
  }
  return resources.appendingPathComponent("INPUTS", isDirectory: true).standardizedFileURL
}()

final class BuildServerBuildSystemTests: XCTestCase {
  private var root: AbsolutePath {
    try! AbsolutePath(
      validating:
        skTestSupportInputsDirectory
        .appendingPathComponent(testDirectoryName, isDirectory: true).path
    )
  }
  let buildFolder = try! AbsolutePath(validating: NSTemporaryDirectory())

  func testServerInitialize() async throws {
    let buildSystem = try await BuildServerBuildSystem(
      projectRoot: root,
      connectionToSourceKitLSP: LocalConnection(receiverName: "Dummy SourceKit-LSP")
    )

    assertEqual(
      await buildSystem.indexDatabasePath,
      try AbsolutePath(validating: "some/index/db/path", relativeTo: root)
    )
    assertEqual(
      await buildSystem.indexStorePath,
      try AbsolutePath(validating: "some/index/store/path", relativeTo: root)
    )
  }

  func testFileRegistration() async throws {
    let uri = DocumentURI(filePath: "/some/file/path", isDirectory: false)
    let expectation = self.expectation(description: "\(uri) settings updated")
    let testMessageHandler = TestMessageHandler(targetExpectations: [
      (DidChangeBuildTargetNotification(changes: nil), expectation)
    ])
    let buildSystem = try await BuildServerBuildSystem(
      projectRoot: root,
      connectionToSourceKitLSP: testMessageHandler.connection
    )
    _ = try await buildSystem.sourceKitOptions(
      request: SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri: uri),
        target: try unwrap(
          await buildSystem.inverseSources(
            request: InverseSourcesRequest(textDocument: TextDocumentIdentifier(uri: uri))
          ).targets.only
        )
      )
    )

    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: defaultTimeout), .completed)
  }

  func testBuildTargetsChanged() async throws {
    let uri = DocumentURI(filePath: "/some/file/path", isDirectory: false)
    let expectation = XCTestExpectation(description: "target changed")
    let testMessageHandler = TestMessageHandler(targetExpectations: [
      (
        DidChangeBuildTargetNotification(changes: [
          BuildTargetEvent(
            target: BuildTargetIdentifier(uri: try! URI(string: "build://target/a")),
            kind: .created,
            dataKind: nil,
            data: LSPAny.dictionary(["key": "value"])
          )
        ]), expectation
      )
    ])
    defer {
      // BuildSystemManager has a weak reference to delegate. Keep it alive.
      _fixLifetime(testMessageHandler)
    }
    let buildSystem = try await BuildServerBuildSystem(
      projectRoot: root,
      connectionToSourceKitLSP: testMessageHandler.connection
    )
    _ = try await buildSystem.sourceKitOptions(
      request: SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri: uri),
        target: try unwrap(
          await buildSystem.inverseSources(
            request: InverseSourcesRequest(textDocument: TextDocumentIdentifier(uri: uri))
          ).targets.only
        )
      )
    )

    try await fulfillmentOfOrThrow([expectation])
  }
}

fileprivate final class TestMessageHandler: MessageHandler {
  let targetExpectations: [(DidChangeBuildTargetNotification, XCTestExpectation)]

  var connection: LocalConnection {
    let connection = LocalConnection(receiverName: "Test message handler")
    connection.start(handler: self)
    return connection
  }

  package init(targetExpectations: [(DidChangeBuildTargetNotification, XCTestExpectation)] = []) {
    self.targetExpectations = targetExpectations
  }

  func didChangeBuildTarget(notification: DidChangeBuildTargetNotification) {
    for (expectedNotification, expectation) in targetExpectations {
      if expectedNotification == notification {
        expectation.fulfill()
      }
    }
  }

  func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) {
    reply(.failure(.methodNotFound(Request.method)))
  }

  func handle(_ notification: some NotificationType) {
    switch notification {
    case let notification as DidChangeBuildTargetNotification:
      didChangeBuildTarget(notification: notification)
    default:
      break
    }
  }
}
