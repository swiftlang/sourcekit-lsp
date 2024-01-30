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

public struct DiagnoseCommand: AsyncParsableCommand {
  public static var configuration: CommandConfiguration = CommandConfiguration(
    commandName: "diagnose",
    abstract: "Reduce sourcekitd crashes",
    shouldDisplay: false
  )

  @Option(
    name: .customLong("request-file"),
    help:
      "Path to a sourcekitd request. If not specified, the command will look for crashed sourcekitd requests and have been logged to OSLog"
  )
  var sourcekitdRequestPath: String?

  @Option(
    name: .customLong("os-log-history"),
    help: "If now request file is passed, how many minutes of OS Log history should be scraped for a crash."
  )
  var osLogScrapeDuration: Int = 60

  @Option(
    name: .customLong("sourcekitd"),
    help:
      "Path to sourcekitd.framework/sourcekitd. If not specified, the toolchain is found in the same way that sourcekit-lsp finds it"
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

  var sourcekitd: String? {
    get async throws {
      if let sourcekitdOverride {
        return sourcekitdOverride
      }

      let installPath = try AbsolutePath(validating: Bundle.main.bundlePath)
      let toolchainRegistry = ToolchainRegistry(installPath: installPath)
      return await toolchainRegistry.default?.sourcekitd?.pathString
    }
  }

  /// Request infos of crashes that should be diagnosed.
  func requestInfos() throws -> [(name: String, info: RequestInfo)] {
    if let sourcekitdRequestPath {
      let request = try String(contentsOfFile: sourcekitdRequestPath)
      return [(sourcekitdRequestPath, try RequestInfo(request: request))]
    }
    #if canImport(OSLog)
    return try OSLogScraper(searchDuration: TimeInterval(osLogScrapeDuration * 60)).getCrashedRequests()
    #else
    throw ReductionError("--request-file must be specified on all platforms other than macOS")
    #endif
  }

  public init() {}

  public func run() async throws {
    guard let sourcekitd = try await sourcekitd else {
      throw ReductionError("Unable to find sourcekitd.framework")
    }

    for (name, requestInfo) in try requestInfos() {
      print("-- Diagnosing \(name)")
      do {
        var requestInfo = requestInfo
        var nspredicate: NSPredicate? = nil
        #if canImport(Darwin)
        if let predicate {
          nspredicate = NSPredicate(format: predicate)
        }
        #endif
        let executor = SourceKitRequestExecutor(
          sourcekitd: URL(fileURLWithPath: sourcekitd),
          reproducerPredicate: nspredicate
        )
        let fileReducer = FileReducer(sourcekitdExecutor: executor)
        requestInfo = try await fileReducer.run(initialRequestInfo: requestInfo)

        let commandLineReducer = CommandLineArgumentReducer(sourcekitdExecutor: executor)
        requestInfo = try await commandLineReducer.run(initialRequestInfo: requestInfo)

        let reproducerBundle = try makeReproducerBundle(for: requestInfo)

        print("----------------------------------------")
        print(
          "Reduced SourceKit crash and created a bundle that contains information to reproduce the issue at the following path."
        )
        print("Please file an issue at https://github.com/apple/sourcekit-lsp/issues/new and attach this bundle")
        print()
        print(reproducerBundle.path)

        // We have found a reproducer. Stop. Looking further probably won't help because other crashes are likely the same cause.
        return
      } catch {
        // Reducing this request failed. Continue reducing the next one, maybe that one succeeds.
        print(error)
      }
    }

    print("No reducible crashes found")
    throw ExitCode(1)
  }
}
