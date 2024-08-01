//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKSupport
import SKTestSupport
import XCTest

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

final class ProcessLaunchTests: XCTestCase {
  func testWorkingDirectory() async throws {
    let project = try await MultiFileTestProject(files: [
      "parent dir/subdir A/a.txt": "",
      "parent dir/subdir B/b.txt": "",
      "parent dir/subdir C/c.txt": "",
    ])

    let ls = try await unwrap(findTool(name: "ls"))

    let result = try await Process.run(
      arguments: [ls.path, "subdir A", "subdir B"],
      workingDirectory: AbsolutePath(validating: project.scratchDirectory.path).appending(component: "parent dir")
    )
    let stdout = try unwrap(String(bytes: result.output.get(), encoding: .utf8))
    XCTAssert(stdout.contains("a.txt"), "Directory did not contain a.txt:\n\(stdout)")
    XCTAssert(stdout.contains("b.txt"), "Directory did not contain b.txt:\n\(stdout)")
    XCTAssert(!stdout.contains("c.txt"), "Directory contained c.txt:\n\(stdout)")
  }
}
