//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import SKCore
import TSCBasic

public class SwiftPMTestWorkspace: MultiFileTestWorkspace {
  enum Error: Swift.Error {
    /// The `swift` executable could not be found.
    case swiftNotFound
  }

  public static let defaultPackageManifest: String = """
    // swift-tools-version: 5.7

    import PackageDescription

    let package = Package(
      name: "MyLibrary",
      targets: [.target(name: "MyLibrary")]
    )
    """

  /// Create a new SwiftPM package with the given files.
  ///
  /// If `index` is `true`, then the package will be built, indexing all modules within the package.
  public init(
    files: [String: String],
    manifest: String = SwiftPMTestWorkspace.defaultPackageManifest,
    index: Bool = false,
    testName: String = #function
  ) async throws {
    var filesByPath: [RelativeFileLocation: String] = [:]
    for (fileName, contents) in files {
      filesByPath[RelativeFileLocation(directories: ["Sources", "MyLibrary"], fileName)] = contents
    }
    filesByPath["Package.swift"] = manifest
    try await super.init(
      files: filesByPath,
      testName: testName
    )

    guard let swift = ToolchainRegistry.shared.default?.swift?.asURL else {
      throw Error.swiftNotFound
    }

    if index {
      try await Process.checkNonZeroExit(arguments: [swift.path, "build", "--package-path", scratchDirectory.path])
    }
    // Wait for the indexstore-db to finish indexing
    _ = try await testClient.send(PollIndexRequest())
  }
}
