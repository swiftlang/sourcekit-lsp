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

import SKCore
import XCTest

final class FileBuildSettingsTests: XCTestCase {

  func testSwiftCompilerArg() throws {
    let swiftFileBuildSettingsWithWorkingDiectory = FileBuildSettings(compilerArguments: ["a", "b"], workingDirectory: "/path/to/root", language: .swift)
    let swiftFileBuildSettingsWithoutWorkingDiectory = FileBuildSettings(compilerArguments: ["a", "b"], language: .swift)
    let swiftFileBuildSettingsWithWorkingDiectoryArg = FileBuildSettings(compilerArguments: ["a", "b", "-working-directory", "/custom-root"], workingDirectory: "/path/to/root", language: .swift)
    let objcFileBuildSettingsWithWorkingDiectory = FileBuildSettings(compilerArguments: ["a", "b"], workingDirectory: "/path/to/root", language: .objective_c)
    XCTAssertEqual(swiftFileBuildSettingsWithWorkingDiectory.compilerArguments, ["a", "b", "-working-directory", "/path/to/root"])
    XCTAssertEqual(swiftFileBuildSettingsWithoutWorkingDiectory.compilerArguments, ["a", "b"])
    XCTAssertEqual(swiftFileBuildSettingsWithWorkingDiectoryArg.compilerArguments, ["a", "b", "-working-directory", "/custom-root"])
    XCTAssertEqual(objcFileBuildSettingsWithWorkingDiectory.compilerArguments, ["a", "b"])
  }
}
