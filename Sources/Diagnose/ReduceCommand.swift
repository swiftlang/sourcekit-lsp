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

public struct ReduceCommand: AsyncParsableCommand {
  public static var configuration: CommandConfiguration = CommandConfiguration(
    commandName: "reduce",
    abstract: "Reduce a single sourcekitd crash",
    shouldDisplay: false
  )

  @Option(name: .customLong("request-file"), help: "Path to a sourcekitd request to reduce.")
  var sourcekitdRequestPath: String

  @Option(
    name: .customLong("sourcekitd"),
    help: """
      Path to sourcekitd.framework/sourcekitd. \
      If not specified, the toolchain is found in the same way that sourcekit-lsp finds it
      """
  )
  var sourcekitdOverride: String?

  #if canImport(Darwin)
  // Creating an NSPredicate from a string is not supported in corelibs-foundation.
  @Option(
    help: """
      If the sourcekitd response matches this predicate, consider it as reproducing the issue.
      sourcekitd crashes are always considered as reproducers.

      The predicate is an NSPredicate and `self` is the sourcekitd response.
      """
  )
  var predicate: String?
  #endif

  var toolchainRegistry: ToolchainRegistry {
    get throws {
      let installPath = try AbsolutePath(validating: Bundle.main.bundlePath)
      return ToolchainRegistry(installPath: installPath)
    }
  }

  var sourcekitd: String? {
    get async throws {
      if let sourcekitdOverride {
        return sourcekitdOverride
      }
      return try await toolchainRegistry.default?.sourcekitd?.pathString
    }
  }

  public init() {}

  public func run() async throws {
    guard let sourcekitd = try await sourcekitd else {
      throw ReductionError("Unable to find sourcekitd.framework")
    }

    let progressBar = PercentProgressAnimation(stream: stderrStream, header: "Reducing sourcekitd issue")

    let request = try String(contentsOfFile: sourcekitdRequestPath)
    var requestInfo = try RequestInfo(request: request)

    var nspredicate: NSPredicate? = nil
    #if canImport(Darwin)
    if let predicate {
      nspredicate = NSPredicate(format: predicate)
    }
    #endif
    let executor = OutOfProcessSourceKitRequestExecutor(
      sourcekitd: URL(fileURLWithPath: sourcekitd),
      reproducerPredicate: nspredicate
    )

    // How much time of the reduction is expected to be spent reducing the source compared to command line argument
    // reduction.
    let sourceReductionPercentage = 0.7

    requestInfo = try await requestInfo.reduceInputFile(using: executor) { progress, message in
      let progress = progress * sourceReductionPercentage
      progressBar.update(step: Int(progress * 100), total: 100, text: message)
    }
    requestInfo = try await requestInfo.reduceCommandLineArguments(using: executor) { progress, message in
      let progress = sourceReductionPercentage + progress * (1 - sourceReductionPercentage)
      progressBar.update(step: Int(progress * 100), total: 100, text: message)
    }

    progressBar.complete(success: true)

    let reducedSourceFile = FileManager.default.temporaryDirectory.appendingPathComponent("reduced.swift")
    try requestInfo.fileContents.write(to: reducedSourceFile, atomically: true, encoding: .utf8)

    print("Reduced Request:")
    print(try requestInfo.request(for: reducedSourceFile))
  }
}
