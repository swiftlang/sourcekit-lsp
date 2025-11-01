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

import SKTestSupport
import SwiftExtensions
import TSCExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

final class ProcessRunTests: XCTestCase {
  func testWorkingDirectory() async throws {
    try await withTestScratchDir { tempDir in
      let workingDir = tempDir.appending(component: "working-dir")
      try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)

      #if os(Windows)
      // On Windows, Python 3 gets installed as python.exe
      let pythonName = "python"
      #else
      let pythonName = "python3"
      #endif
      let python = try await unwrap(findTool(name: pythonName))

      let pythonFile = tempDir.appending(component: "show-cwd.py")
      try """
      import os
      print(os.getcwd(), end='')
      """.write(to: pythonFile, atomically: true, encoding: .utf8)

      let result = try await withTimeout(defaultTimeoutDuration) {
        try await Process.run(
          arguments: [python.filePath, pythonFile.filePath],
          workingDirectory: AbsolutePath(validating: workingDir.filePath)
        )
      }
      let stdout = try unwrap(String(bytes: result.output.get(), encoding: .utf8))
      XCTAssertEqual(stdout, try workingDir.filePath)
    }
  }
}
