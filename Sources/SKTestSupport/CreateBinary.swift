//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Foundation
import SwiftExtensions
import ToolchainRegistry
import XCTest

import class TSCBasic.Process

/// Compiles the given Swift source code into a binary at `executablePath`.
package func createBinary(_ sourceCode: String, at executablePath: URL) async throws {
  try await withTestScratchDir { scratchDir in
    let sourceFile = scratchDir.appending(component: "source.swift")
    try await sourceCode.writeWithRetry(to: sourceFile)

    var compilerArguments = try [
      sourceFile.filePath,
      "-o",
      executablePath.filePath,
    ]
    if let defaultSDKPath {
      compilerArguments += ["-sdk", defaultSDKPath]
    }
    try await Process.checkNonZeroExit(
      arguments: [unwrap(ToolchainRegistry.forTesting.default?.swiftc?.filePath)] + compilerArguments
    )
  }
}
