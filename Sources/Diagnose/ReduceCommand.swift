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

package import ArgumentParser
import Foundation
import SourceKitD
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import class TSCUtility.PercentProgressAnimation

package struct ReduceCommand: AsyncParsableCommand {
  package static let configuration: CommandConfiguration = CommandConfiguration(
    commandName: "reduce",
    abstract: "Reduce a single sourcekitd crash"
  )

  @Option(name: .customLong("request-file"), help: "Path to a sourcekitd request to reduce.")
  var sourcekitdRequestPath: String

  @Option(
    name: .customLong("toolchain"),
    help: """
      The toolchain used to reduce the sourcekitd issue. \
      If not specified, the toolchain is found in the same way that sourcekit-lsp finds it
      """
  )
  var toolchainOverride: String?

  #if canImport(Darwin)
  // Creating an NSPredicate from a string is not supported in corelibs-foundation.
  @Option(
    help: """
      If the sourcekitd response matches this predicate, consider it as reproducing the issue.
      sourcekitd crashes are always considered as reproducers.

      The predicate is an NSPredicate. `stdout` and `stderr` are standard output and standard error of the \
      sourcekitd execution using `sourcekit-lsp run-sourcekitd-request`, respectively.
      """
  )
  var predicate: String?

  private var nsPredicate: NSPredicate? {
    guard let predicate else {
      return nil
    }
    return NSPredicate(format: predicate)
  }
  #else
  private var nsPredicate: NSPredicate? { nil }
  #endif

  @MainActor
  var toolchain: Toolchain? {
    get async throws {
      if let toolchainOverride {
        return Toolchain(URL(fileURLWithPath: toolchainOverride))
      }
      return await ToolchainRegistry(installPath: Bundle.main.bundleURL).default
    }
  }

  package init() {}

  @MainActor
  package func run() async throws {
    guard let toolchain = try await toolchain else {
      throw GenericError("Unable to find toolchain")
    }
    guard let sourcekitd = toolchain.sourcekitd else {
      throw GenericError("Unable to find sourcekitd.framework")
    }
    guard let swiftFrontend = toolchain.swiftFrontend else {
      throw GenericError("Unable to find sourcekitd.framework")
    }
    let pluginPaths = toolchain.pluginPaths

    let progressBar = PercentProgressAnimation(stream: stderrStreamConcurrencySafe, header: "Reducing sourcekitd issue")

    let request = try String(contentsOfFile: sourcekitdRequestPath, encoding: .utf8)
    let requestInfo = try RequestInfo(request: request)

    let executor = OutOfProcessSourceKitRequestExecutor(
      sourcekitd: sourcekitd,
      pluginPaths: pluginPaths,
      swiftFrontend: swiftFrontend,
      reproducerPredicate: nsPredicate
    )

    let reduceRequestInfo = try await requestInfo.reduce(using: executor) { progress, message in
      progressBar.update(step: Int(progress * 100), total: 100, text: message)
    }

    progressBar.complete(success: true)

    let reducedSourceFile = FileManager.default.temporaryDirectory.appending(component: "reduced.swift")
    try reduceRequestInfo.fileContents.write(to: reducedSourceFile, atomically: true, encoding: .utf8)

    print("Reduced Request:")
    print(try reduceRequestInfo.requests(for: reducedSourceFile).joined(separator: "\n\n\n\n"))
  }
}
