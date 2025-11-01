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
}
