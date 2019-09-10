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
import SKCore
import TSCBasic
import LanguageServerProtocol
import Foundation

final class BuildServerBuildSystemTests: XCTestCase {

  func testServerInitialize() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildFolder = AbsolutePath(NSTemporaryDirectory())

    let buildSystem = try? BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    XCTAssertNotNil(buildSystem)
    XCTAssertEqual(buildSystem!.indexStorePath, AbsolutePath("some/index/store/path", relativeTo: root))
  }

  func testSettings() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildFolder = AbsolutePath(NSTemporaryDirectory())
    let buildSystem = try? BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)
    XCTAssertNotNil(buildSystem)

    // test settings with a response
    let fileURL = URL(fileURLWithPath: "/path/to/some/file.swift")
    let settings = buildSystem?.settings(for: fileURL, Language.swift)
    XCTAssertEqual(settings?.compilerArguments, ["-a", "-b"])
    XCTAssertEqual(settings?.workingDirectory, fileURL.deletingLastPathComponent().path)

    // test error
    let missingFileURL = URL(fileURLWithPath: "/path/to/some/missingfile.missing")
    XCTAssertNil(buildSystem?.settings(for: missingFileURL, Language.swift))
  }

  func testFileRegistration() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildFolder = AbsolutePath(NSTemporaryDirectory())
    let buildSystem = try? BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)
    XCTAssertNotNil(buildSystem)

    let fileUrl = URL(fileURLWithPath: "/some/file/path")
    let expectation = XCTestExpectation(description: "\(fileUrl) settings updated")
    let buildSystemDelegate = TestDelegate(expectations: [fileUrl: expectation])
    buildSystem?.delegate = buildSystemDelegate
    buildSystem?.registerForChangeNotifications(for: fileUrl)

    let result = XCTWaiter.wait(for: [expectation], timeout: 1)
    if result != .completed {
      fatalError("error \(result) waiting for settings notification")
    }
  }

}

final class TestDelegate: BuildSystemDelegate {

  let expectations: [URL:XCTestExpectation]

  public init(expectations: [URL:XCTestExpectation]) {
    self.expectations = expectations
  }

  func fileBuildSettingsChanged(_ changedFiles: Set<URL>) {
    for url in changedFiles {
      expectations[url]?.fulfill()
    }
  }
}
