//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import ISDBTestSupport
import XCTest

fileprivate let sdkArgs =
  if let defaultSDKPath {
    """
    "-sdk", "\(defaultSDKPath)",
    """
  } else {
    ""
  }

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

/// Creates a project that uses a BSP server to provide build settings.
///
/// The build server is implemented in Python on top of the code in `AbstractBuildServer.py`.
///
/// The build server can contain `$SDK_ARGS`, which will replaced by `"-sdk", "/path/to/sdk"` on macOS and by an empty
/// string on all other platforms.
package class BuildServerTestProject: MultiFileTestProject {
  package init(
    files: [RelativeFileLocation: String],
    buildServer: String,
    testName: String = #function
  ) async throws {
    var files = files
    files["buildServer.json"] = """
      {
        "name": "client name",
        "version": "10",
        "bspVersion": "2.0",
        "languages": ["a", "b"],
        "argv": ["server.py"]
      }
      """
    files["server.py"] = """
      import sys
      from typing import Dict, List, Optional

      sys.path.append("\(skTestSupportInputsDirectory.path)")

      from AbstractBuildServer import AbstractBuildServer, LegacyBuildServer

      \(buildServer)

      BuildServer().run()
      """.replacing("$SDK_ARGS", with: sdkArgs)
    try await super.init(
      files: files,
      testName: testName
    )
  }
}
