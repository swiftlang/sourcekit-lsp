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

package import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
import SwiftExtensions
import TSCExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv
import struct TSCBasic.ProcessResult

/// A SwiftPM package that gets written to disk and for which a Git repository is initialized with a commit tagged
/// `1.0.0`. This repository can then be used as a dependency for another package, usually a `SwiftPMTestProject`.
package class SwiftPMDependencyProject {
  /// The scratch directory created for the dependency project.
  package let scratchDirectory: URL

  /// The directory in which the repository lives.
  package var packageDirectory: URL {
    return scratchDirectory.appending(component: "MyDependency")
  }

  private func runGitCommand(_ arguments: [String], workingDirectory: URL) async throws {
    enum Error: Swift.Error {
      case cannotFindGit
      case processedTerminatedWithNonZeroExitCode(ProcessResult)
    }
    guard let git = await findTool(name: "git") else {
      if ProcessEnv.block["SWIFTCI_USE_LOCAL_DEPS"] == nil {
        // Never skip the test in CI, similar to what SkipUnless does.
        throw XCTSkip("git cannot be found")
      }
      throw Error.cannotFindGit
    }
    // We can't use `workingDirectory` because Amazon Linux doesn't support working directories (or at least
    // TSCBasic.Process doesn't support working directories on Amazon Linux)
    let processResult = try await withTimeout(defaultTimeoutDuration) {
      try await TSCBasic.Process.run(
        arguments: [try git.filePath, "-C", try workingDirectory.filePath] + arguments,
        workingDirectory: nil
      )
    }
    guard processResult.exitStatus == .terminated(code: 0) else {
      throw Error.processedTerminatedWithNonZeroExitCode(processResult)
    }
  }

  package static let defaultPackageManifest: String = """
    // swift-tools-version: 5.7

    import PackageDescription

    let package = Package(
      name: "MyDependency",
      products: [.library(name: "MyDependency", targets: ["MyDependency"])],
      targets: [.target(name: "MyDependency")]
    )
    """

  package init(
    files: [RelativeFileLocation: String],
    manifest: String = defaultPackageManifest,
    testName: String = #function
  ) async throws {
    scratchDirectory = try testScratchDir(testName: testName)

    var files = files
    files["Package.swift"] = manifest

    for (fileLocation, markedContents) in files {
      let fileURL = fileLocation.url(relativeTo: packageDirectory)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try extractMarkers(markedContents).textWithoutMarkers.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    try await runGitCommand(["init"], workingDirectory: packageDirectory)
    try await tag(changedFiles: files.keys.map { $0.url(relativeTo: packageDirectory) }, version: "1.0.0")
  }

  package func tag(changedFiles: [URL], version: String) async throws {
    try await runGitCommand(
      ["add"] + changedFiles.map { try $0.filePath },
      workingDirectory: packageDirectory
    )
    try await runGitCommand(
      [
        "-c", "user.name=Dummy", "-c", "user.email=noreply@swift.org",
        "commit", "--no-gpg-sign", "-m", "Version \(version)",
      ],
      workingDirectory: packageDirectory
    )

    try await runGitCommand(["tag", version], workingDirectory: self.packageDirectory)
  }

  deinit {
    if cleanScratchDirectories {
      try? FileManager.default.removeItem(at: scratchDirectory)
    }
  }

  /// Function that makes sure the project stays alive until this is called. Otherwise, the `SwiftPMDependencyProject`
  /// might get deinitialized, which deletes the package on disk.
  package func keepAlive() {
    withExtendedLifetime(self) { _ in }
  }
}
