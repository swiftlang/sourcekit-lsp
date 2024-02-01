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
      "Path to a sourcekitd request. If not specified, the command will look for crashed sourcekitd requests that have been logged to OSLog"
  )
  var sourcekitdRequestPath: String?

  @Option(
    name: .customLong("os-log-history"),
    help: "If no request file is passed, how many minutes of OS Log history should be scraped for a crash."
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

    var reproducerBundle: URL?
    for (name, requestInfo) in try requestInfos() {
      print("-- Diagnosing \(name)")
      do {
        reproducerBundle = try await reduce(requestInfo: requestInfo, sourcekitd: sourcekitd)
        // If reduce didn't throw, we have found a reproducer. Stop.
        // Looking further probably won't help because other crashes are likely the same cause.
        break
      } catch {
        // Reducing this request failed. Continue reducing the next one, maybe that one succeeds.
        print(error)
      }
    }

    guard let reproducerBundle else {
      print("No reducible crashes found")
      throw ExitCode(1)
    }
    print(
      """
        ----------------------------------------
        Reduced SourceKit issue and created a bundle that contains a reduced sourcekitd request exhibiting the issue
        and all the files referenced from the request.
        The information in this bundle should be sufficient to reproduce the issue.

        Please file an issue at https://github.com/apple/sourcekit-lsp/issues/new and attach the bundle located at
        \(reproducerBundle.path)
      """
    )

  }

  private func reduce(requestInfo: RequestInfo, sourcekitd: String) async throws -> URL {
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
    requestInfo = try await requestInfo.reduceInputFile(using: executor)
    requestInfo = try await requestInfo.reduceCommandLineArguments(using: executor)

    return try makeReproducerBundle(for: requestInfo)
  }
}
