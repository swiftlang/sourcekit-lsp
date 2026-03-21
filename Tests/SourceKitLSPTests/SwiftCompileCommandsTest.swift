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

import BuildServerIntegration
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftLanguageService
@_spi(ExperimentalLanguageFeatures) import SwiftParser
import XCTest

final class SwiftCompileCommandsTest: SourceKitLSPTestCase {
  func testWorkingDirectoryIsAdded() {
    let settings = FileBuildSettings(compilerArguments: ["a", "b"], workingDirectory: "/build/root", language: .swift)
    let compileCommand = SwiftCompileCommand(settings)
    XCTAssertEqual(compileCommand.compilerArgs, ["a", "b", "-working-directory", "/build/root"])
  }

  func testNoWorkingDirectory() {
    let settings = FileBuildSettings(compilerArguments: ["a", "b"], language: .swift)
    let compileCommand = SwiftCompileCommand(settings)
    XCTAssertEqual(compileCommand.compilerArgs, ["a", "b"])
  }

  func testPreexistingWorkingDirectoryArg() {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "b", "-working-directory", "/custom-root"],
      workingDirectory: "/build/root",
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    XCTAssertEqual(compileCommand.compilerArgs, ["a", "b", "-working-directory", "/custom-root"])
  }

  func testExperimentalFeaturesExtraction() {
    let settings = FileBuildSettings(
      compilerArguments: [
        "a", "-enable-experimental-feature", "_test_EverythingUnexpected", "b",
      ],
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let features = compileCommand.experimentalFeatures
    XCTAssertEqual(features, [._test_EverythingUnexpected])
  }

  func testExperimentalFeaturesColonSuffix() {
    // Feature names with a colon suffix like "FeatureName:adoption" should
    // still be recognized by stripping the colon and everything after it.
    let settings = FileBuildSettings(
      compilerArguments: [
        "-enable-experimental-feature", "_test_EverythingUnexpected:adoption",
      ],
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let features = compileCommand.experimentalFeatures
    XCTAssertEqual(
      features,
      [._test_EverythingUnexpected],
      "Expected ._test_EverythingUnexpected to be extracted from '_test_EverythingUnexpected:adoption'"
    )
  }

  func testExperimentalFeaturesEmpty() {
    let settings = FileBuildSettings(compilerArguments: ["a", "b"], language: .swift)
    let compileCommand = SwiftCompileCommand(settings)
    XCTAssertEqual(compileCommand.experimentalFeatures, [], "Expected no experimental features when none are specified")
  }

  func testExperimentalFeaturesUnknownIgnored() {
    let settings = FileBuildSettings(
      compilerArguments: [
        "-enable-experimental-feature", "SomeUnknownFeature",
        "-enable-experimental-feature", "_test_EverythingUnexpected",
      ],
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let features = compileCommand.experimentalFeatures
    // Unknown features should be silently ignored
    XCTAssertEqual(
      features,
      [._test_EverythingUnexpected],
      "Expected only ._test_EverythingUnexpected, unknown features should be ignored"
    )
  }
}
