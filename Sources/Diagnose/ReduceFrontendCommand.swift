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

import ArgumentParser
import Foundation
import SKCore

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import var TSCBasic.stderrStream
import class TSCUtility.PercentProgressAnimation

public struct ReduceFrontendCommand: AsyncParsableCommand {
  public static let configuration: CommandConfiguration = CommandConfiguration(
    commandName: "reduce-frontend",
    abstract: "Reduce a single swift-frontend crash"
  )

  #if canImport(Darwin)
  // Creating an NSPredicate from a string is not supported in corelibs-foundation.
  @Option(
    help: """
      If the sourcekitd response matches this predicate, consider it as reproducing the issue.
      sourcekitd crashes are always considered as reproducers.

      The predicate is an NSPredicate. `stdout` and `stderr` are standard output and standard error of the \
      swift-frontend execution, respectively.

      Example:
       - stderr CONTAINS "failed to produce diagnostic for expression"
      """
  )
  var predicate: String?

  private var nsPredicate: NSPredicate? { predicate.map { NSPredicate(format: $0) } }
  #else
  private var nsPredicate: NSPredicate? { nil }
  #endif

  @Option(
    name: .customLong("toolchain"),
    help: """
      The toolchain used to reduce the swift-frontend issue. \
      If not specified, the toolchain is found in the same way that sourcekit-lsp finds it
      """
  )
  var toolchainOverride: String?

  @Option(
    parsing: .remaining,
    help: """
      The swift-frontend arguments that exhibit the issue that should be reduced.
      """
  )
  var frontendArgs: [String]

  @MainActor
  var toolchain: Toolchain? {
    get async throws {
      if let toolchainOverride {
        return Toolchain(try AbsolutePath(validating: toolchainOverride))
      }
      let installPath = try AbsolutePath(validating: Bundle.main.bundlePath)
      return await ToolchainRegistry(installPath: installPath).default
    }
  }

  public init() {}

  @MainActor
  public func run() async throws {
    guard let sourcekitd = try await toolchain?.sourcekitd else {
      throw ReductionError("Unable to find sourcekitd.framework")
    }
    guard let swiftFrontend = try await toolchain?.swiftFrontend else {
      throw ReductionError("Unable to find swift-frontend")
    }

    let progressBar = PercentProgressAnimation(
      stream: stderrStream,
      header: "Reducing swift-frontend crash"
    )

    let executor = OutOfProcessSourceKitRequestExecutor(
      sourcekitd: sourcekitd.asURL,
      swiftFrontend: swiftFrontend,
      reproducerPredicate: nsPredicate
    )

    defer {
      progressBar.complete(success: true)
    }
    let reducedRequestInfo = try await reduceFrontendIssue(
      frontendArgs: frontendArgs,
      using: executor
    ) { progress, message in
      progressBar.update(step: Int(progress * 100), total: 100, text: message)
    }

    print("Reduced compiler arguments:")
    print(reducedRequestInfo.compilerArgs.joined(separator: " "))

    print("")
    print("Reduced file contents:")
    print(reducedRequestInfo.fileContents)
  }
}
