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
import SKCore
import SKTestSupport
import TSCBasic
import XCTest

final class BuildServerBuildSystemTests: XCTestCase {

  var root: AbsolutePath {
    AbsolutePath(XCTestCase.sklspInputsDirectory
      .appendingPathComponent(testDirectoryName, isDirectory: true).path)
  } 
  let buildFolder = AbsolutePath(NSTemporaryDirectory())

  func testServerInitialize() throws {
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    XCTAssertEqual(buildSystem.indexDatabasePath, AbsolutePath("some/index/db/path", relativeTo: root))
    XCTAssertEqual(buildSystem.indexStorePath, AbsolutePath("some/index/store/path", relativeTo: root))
  }

  func testSettings() throws {
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

    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
  }

  func testBuildTargets() throws {
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    let expectation = XCTestExpectation(description: "build target expectation")

    buildSystem.buildTargets(reply: { response in
      switch(response) {
      case .success(let targets):
        XCTAssertEqual(targets, [
                       BuildTarget(id: BuildTargetIdentifier(uri: DocumentURI(string: "target:first_target")),
                                   displayName: "First Target",
                                   baseDirectory: DocumentURI(URL(fileURLWithPath: "/some/dir")),
                                   tags: [BuildTargetTag.library, BuildTargetTag.test],
                                   capabilities: BuildTargetCapabilities(canCompile: true, canTest: true, canRun: false),
                                   languageIds: [Language.objective_c, Language.swift],
                                   dependencies: []),
                       BuildTarget(id: BuildTargetIdentifier(uri: DocumentURI(string: "target:second_target")),
                                   displayName: "Second Target",
                                   baseDirectory: DocumentURI(URL(fileURLWithPath: "/some/dir")),
                                   tags: [BuildTargetTag.library, BuildTargetTag.test],
                                   capabilities: BuildTargetCapabilities(canCompile: true, canTest: false, canRun: false),
                                   languageIds: [Language.objective_c, Language.swift],
                                   dependencies: [BuildTargetIdentifier(uri: DocumentURI(string: "target:first_target"))]),
                       ])
        expectation.fulfill()
      case .failure(let error):
        XCTFail(error.message)
      }
    })
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
  }

  func testBuildTargetSources() throws {
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    let expectation = XCTestExpectation(description: "build target sources expectation")
    let targets = [
      BuildTargetIdentifier(uri: DocumentURI(string: "build://target/a")),
      BuildTargetIdentifier(uri: DocumentURI(string: "build://target/b")),
    ]
    buildSystem.buildTargetSources(targets: targets, reply: { response in
      switch(response) {
      case .success(let items):
        XCTAssertNotNil(items)
        XCTAssertEqual(items[0].target.uri, targets[0].uri)
        XCTAssertEqual(items[1].target.uri, targets[1].uri)
        XCTAssertEqual(items[0].sources[0].uri, DocumentURI(URL(fileURLWithPath: "/path/to/a/file")))
        XCTAssertEqual(items[0].sources[0].kind, SourceItemKind.file)
        XCTAssertEqual(items[0].sources[1].uri, DocumentURI(URL(fileURLWithPath: "/path/to/a/folder", isDirectory: true)))
        XCTAssertEqual(items[0].sources[1].kind, SourceItemKind.directory)
        XCTAssertEqual(items[1].sources[0].uri, DocumentURI(URL(fileURLWithPath: "/path/to/b/file")))
        XCTAssertEqual(items[1].sources[0].kind, SourceItemKind.file)
        XCTAssertEqual(items[1].sources[1].uri, DocumentURI(URL(fileURLWithPath: "/path/to/b/folder", isDirectory: true)))
        XCTAssertEqual(items[1].sources[1].kind, SourceItemKind.directory)
        expectation.fulfill()
      case .failure(let error):
        XCTFail(error.message)
      }
    })
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
  }

  func testBuildTargetOutputs() throws {
    let buildSystem = try BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    let expectation = XCTestExpectation(description: "build target output expectation")
    let targets = [
      BuildTargetIdentifier(uri: DocumentURI(string: "build://target/a")),
    ]
    buildSystem.buildTargetOutputPaths(targets: targets, reply: { response in
      switch(response) {
      case .success(let items):
        XCTAssertNotNil(items)
        XCTAssertEqual(items[0].target.uri, targets[0].uri)
        XCTAssertEqual(items[0].outputPaths, [
          DocumentURI(URL(fileURLWithPath: "/path/to/a/file")),
          DocumentURI(URL(fileURLWithPath: "/path/to/a/file2")),
        ])
        expectation.fulfill()
      case .failure(let error):
        XCTFail(error.message)
      }
    })
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
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

    let result = XCTWaiter.wait(for: [expectation], timeout: 15)
    if result != .completed {
      fatalError("error \(result) waiting for targets changed notification")
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
}
