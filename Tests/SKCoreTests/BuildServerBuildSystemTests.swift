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
import Basic
import LanguageServerProtocol

final class BuildServerBuildSystemTests: XCTestCase {

  func testServerInitialize() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildFolder = AbsolutePath(NSTemporaryDirectory())

    let buildSystem = try? BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    XCTAssertNotNil(buildSystem)
    XCTAssertEqual(buildSystem!.indexStorePath, AbsolutePath("some/index/store/path", relativeTo: root))
  }

}
