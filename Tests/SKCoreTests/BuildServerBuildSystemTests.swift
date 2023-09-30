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
import Foundation
import LanguageServerProtocol
import LSPTestSupport
import SKCore
import SKTestSupport
import TSCBasic
import XCTest

final class BuildServerBuildSystemTests: XCTestCase {

  var root: AbsolutePath {
    try! AbsolutePath(validating: XCTestCase.sklspInputsDirectory
      .appendingPathComponent(testDirectoryName, isDirectory: true).path)
  } 
  let buildFolder = try! AbsolutePath(validating: NSTemporaryDirectory())

  func testServerInitialize() throws {
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    XCTAssertEqual(
      buildSystem.indexDatabasePath,
      try AbsolutePath(validating: "some/index/db/path", relativeTo: root)
    )
    XCTAssertEqual(
      buildSystem.indexStorePath, 
      try AbsolutePath(validating: "some/index/store/path", relativeTo: root)
    )
  }

  func testSettings() throws {
#if os(Windows)
    try XCTSkipIf(true, "hang")
#endif
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    // test settings with a response
    let fileURL = URL(fileURLWithPath: "/path/to/some/file.swift")
    let settings = buildSystem._settings(for: DocumentURI(fileURL))
    XCTAssertNotNil(settings)
    XCTAssertEqual(settings?.compilerArguments, ["-a", "-b"])
    XCTAssertEqual(settings?.workingDirectory, fileURL.deletingLastPathComponent().path)

    // test error
    let missingFileURL = URL(fileURLWithPath: "/path/to/some/missingfile.missing")
    XCTAssertNil(buildSystem._settings(for: DocumentURI(missingFileURL)))
  }

  func testFileRegistration() throws {
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    let fileUrl = URL(fileURLWithPath: "/some/file/path")
    let expectation = XCTestExpectation(description: "\(fileUrl) settings updated")
    let buildSystemDelegate = TestDelegate(settingsExpectations: [DocumentURI(fileUrl): expectation])
    defer {
      // BuildSystemManager has a weak reference to delegate. Keep it alive.
      _fixLifetime(buildSystemDelegate)
    }
    buildSystem.delegate = buildSystemDelegate
    buildSystem.registerForChangeNotifications(for: DocumentURI(fileUrl), language: .swift)

    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: defaultTimeout), .completed)
  }

  func testBuildTargetsChanged() throws {
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    let fileUrl = URL(fileURLWithPath: "/some/file/path")
    let expectation = XCTestExpectation(description: "target changed")
    let targetIdentifier = BuildTargetIdentifier(uri: DocumentURI(string: "build://target/a"))
    let buildSystemDelegate = TestDelegate(targetExpectations: [
      BuildTargetEvent(target: targetIdentifier,
        kind: .created,
        data: .dictionary(["key": "value"])): expectation,
    ])
    defer {
      // BuildSystemManager has a weak reference to delegate. Keep it alive.
      _fixLifetime(buildSystemDelegate)
    }
    buildSystem.delegate = buildSystemDelegate
    buildSystem.registerForChangeNotifications(for: DocumentURI(fileUrl), language: .swift)

    let result = XCTWaiter.wait(for: [expectation], timeout: defaultTimeout)
    guard result == .completed else {
      XCTFail("error \(result) waiting for targets changed notification")
      return
    }
  }
}

final class TestDelegate: BuildSystemDelegate {

  let settingsExpectations: [DocumentURI: XCTestExpectation]
  let targetExpectations: [BuildTargetEvent:XCTestExpectation]
  let dependenciesUpdatedExpectations: [DocumentURI:XCTestExpectation]

  public init(settingsExpectations: [DocumentURI:XCTestExpectation] = [:],
              targetExpectations: [BuildTargetEvent:XCTestExpectation] = [:],
              dependenciesUpdatedExpectations: [DocumentURI:XCTestExpectation] = [:]) {
    self.settingsExpectations = settingsExpectations
    self.targetExpectations = targetExpectations
    self.dependenciesUpdatedExpectations = dependenciesUpdatedExpectations
  }

  func buildTargetsChanged(_ changes: [BuildTargetEvent]) {
    for event in changes {
      targetExpectations[event]?.fulfill()
    }
  }

  func fileBuildSettingsChanged(
    _ changedFiles: [DocumentURI: FileBuildSettingsChange]) {
    for (uri, _) in changedFiles {
      settingsExpectations[uri]?.fulfill()
    }
  }

  public func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {
    for uri in changedFiles {
      dependenciesUpdatedExpectations[uri]?.fulfill()
    }
  }

  func fileHandlingCapabilityChanged() {}
}
