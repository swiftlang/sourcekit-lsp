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
    let buildSystem = try await BuildServerBuildSystem(projectRoot: root)

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
    let buildSystem = try await BuildServerBuildSystem(projectRoot: root)

    let fileUrl = URL(fileURLWithPath: "/some/file/path")
    let expectation = XCTestExpectation(description: "\(fileUrl) settings updated")
    let buildSystemDelegate = TestDelegate(settingsExpectations: [DocumentURI(fileUrl): expectation])
    defer {
      // BuildSystemManager has a weak reference to delegate. Keep it alive.
      _fixLifetime(buildSystemDelegate)
    }
    await buildSystem.setDelegate(buildSystemDelegate)
    await buildSystem.registerForChangeNotifications(for: DocumentURI(fileUrl))

    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: defaultTimeout), .completed)
  }

  func testBuildTargetsChanged() async throws {
    let buildSystem = try await BuildServerBuildSystem(projectRoot: root)

    let fileUrl = URL(fileURLWithPath: "/some/file/path")
    let expectation = XCTestExpectation(description: "target changed")
    let buildSystemDelegate = TestDelegate(targetExpectations: [
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
      _fixLifetime(buildSystemDelegate)
    }
    await buildSystem.setMessageHandler(buildSystemDelegate)
    await buildSystem.registerForChangeNotifications(for: DocumentURI(fileUrl))

    try await fulfillmentOfOrThrow([expectation])
  }
}

final class TestDelegate: BuildSystemDelegate, BuiltInBuildSystemMessageHandler {
  let settingsExpectations: [DocumentURI: XCTestExpectation]
  let targetExpectations: [(DidChangeBuildTargetNotification, XCTestExpectation)]
  let dependenciesUpdatedExpectations: [DocumentURI: XCTestExpectation]

  package init(
    settingsExpectations: [DocumentURI: XCTestExpectation] = [:],
    targetExpectations: [(DidChangeBuildTargetNotification, XCTestExpectation)] = [],
    dependenciesUpdatedExpectations: [DocumentURI: XCTestExpectation] = [:]
  ) {
    self.settingsExpectations = settingsExpectations
    self.targetExpectations = targetExpectations
    self.dependenciesUpdatedExpectations = dependenciesUpdatedExpectations
  }

  func didChangeBuildTarget(notification: DidChangeBuildTargetNotification) {
    for (expectedNotification, expectation) in targetExpectations {
      if expectedNotification == notification {
        expectation.fulfill()
      }
    }
  }

  func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) {
    for uri in changedFiles {
      settingsExpectations[uri]?.fulfill()
    }
  }

  package func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {
    for uri in changedFiles {
      dependenciesUpdatedExpectations[uri]?.fulfill()
    }
  }

  func fileHandlingCapabilityChanged() {}

  func sendRequestToSourceKitLSP<R: RequestType>(_ request: R) async throws -> R.Response {
    throw ResponseError.methodNotFound(R.method)
  }

  func sendNotificationToSourceKitLSP(_ notification: some NotificationType) async {
    switch notification {
    case let notification as DidChangeBuildTargetNotification:
      didChangeBuildTarget(notification: notification)
    default:
      break
    }
  }
}
