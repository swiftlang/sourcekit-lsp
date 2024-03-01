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

public struct DiagnoseCommand: AsyncParsableCommand {
  public static var configuration: CommandConfiguration = CommandConfiguration(
    commandName: "diagnose",
    abstract: "Creates a bundle containing information that help diagnose issues with sourcekit-lsp"
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

  private func addSourcekitdCrashReproducer(toBundle bundlePath: URL) async throws {
    guard let sourcekitd = try await sourcekitd else {
      throw ReductionError("Unable to find sourcekitd.framework")
    }

    for (name, requestInfo) in try requestInfos() {
      print("-- Reducing \(name)")
      do {
        try await reduce(
          requestInfo: requestInfo,
          sourcekitd: sourcekitd,
          bundlePath: bundlePath.appendingPathComponent("reproducer")
        )
        // If reduce didn't throw, we have found a reproducer. Stop.
        // Looking further probably won't help because other crashes are likely the same cause.
        break
      } catch {
        // Reducing this request failed. Continue reducing the next one, maybe that one succeeds.
        print(error)
      }
    }
  }

  /// Execute body and if it throws, log the error.
  private func orPrintError(_ body: () async throws -> Void) async {
    do {
      try await body()
    } catch {
      print(error)
    }
  }

  private func addOsLog(toBundle bundlePath: URL) async throws {
    #if os(macOS)
    print("-- Collecting log messages")
    let outputFileUrl = bundlePath.appendingPathComponent("log.txt")
    FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: outputFileUrl)
    let process = Process(
      arguments: [
        "/usr/bin/log",
        "show",
        "--predicate", #"subsystem = "org.swift.sourcekit-lsp" AND process = "sourcekit-lsp""#,
        "--info",
        "--debug",
      ],
      outputRedirection: .stream(
        stdout: { try? fileHandle.write(contentsOf: $0) },
        stderr: { _ in }
      )
    )
    try process.launch()
    try await process.waitUntilExit()
    #endif
  }

  private func addCrashLogs(toBundle bundlePath: URL) throws {
    #if os(macOS)
    print("-- Collecting crash reports")

    let destinationDir = bundlePath.appendingPathComponent("crashes")
    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

    let processesToIncludeCrashReportsOf = ["SourceKitService", "sourcekit-lsp", "swift-frontend"]
    let directoriesToScanForCrashReports = ["/Library/Logs/DiagnosticReports", "~/Library/Logs/DiagnosticReports"]

    for directoryToScan in directoriesToScanForCrashReports {
      let diagnosticReports = URL(filePath: (directoryToScan as NSString).expandingTildeInPath)
      let enumerator = FileManager.default.enumerator(at: diagnosticReports, includingPropertiesForKeys: nil)
      while let fileUrl = enumerator?.nextObject() as? URL {
        guard processesToIncludeCrashReportsOf.contains(where: { fileUrl.lastPathComponent.hasPrefix($0) }) else {
          continue
        }
        try? FileManager.default.copyItem(
          at: fileUrl,
          to: destinationDir.appendingPathComponent(fileUrl.lastPathComponent)
        )
      }
    }
    #endif
  }

  private func addSwiftVersion(toBundle bundlePath: URL) async throws {
    print("-- Collecting installed Swift versions")

    let outputFileUrl = bundlePath.appendingPathComponent("swift-versions.txt")
    FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: outputFileUrl)

    for toolchain in try await toolchainRegistry.toolchains {
      guard let swiftUrl = toolchain.swift?.asURL else {
        continue
      }

      try fileHandle.write(contentsOf: "\(swiftUrl.path) --version\n".data(using: .utf8)!)
      let process = Process(
        arguments: [swiftUrl.path, "--version"],
        outputRedirection: .stream(
          stdout: { try? fileHandle.write(contentsOf: $0) },
          stderr: { _ in }
        )
      )
      try process.launch()
      try await process.waitUntilExit()
      fileHandle.write("\n".data(using: .utf8)!)
    }
  }

  public func run() async throws {
    print(
      """
      sourcekit-lsp diagnose collects information that helps the developers of sourcekit-lsp diagnose and fix issues. 
      This information contains:
      - Crash logs from SourceKit
      - Log messages emitted by SourceKit
      - Versions of Swift installed on your system
      - If possible, a minimized project that caused SourceKit to crash

      All information is collected locally.
      The collection might take a few minutes.
      ----------------------------------------
      """
    )

    let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let bundlePath = FileManager.default.temporaryDirectory
      .appendingPathComponent("sourcekitd-reproducer-\(date)")
    try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)

    await orPrintError { try addCrashLogs(toBundle: bundlePath) }
    await orPrintError { try await addOsLog(toBundle: bundlePath) }
    await orPrintError { try await addSwiftVersion(toBundle: bundlePath) }
    await orPrintError { try await addSourcekitdCrashReproducer(toBundle: bundlePath) }

    print(
      """
      ----------------------------------------
      Bundle created. 
      When filing an issue at https://github.com/apple/sourcekit-lsp/issues/new, 
      please attach the bundle located at 
      \(bundlePath.path)
      """
    )

  }

  private func reduce(requestInfo: RequestInfo, sourcekitd: String, bundlePath: URL) async throws {
    var requestInfo = requestInfo
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
    requestInfo = try await requestInfo.reduceInputFile(using: executor)
    requestInfo = try await requestInfo.reduceCommandLineArguments(using: executor)

    try makeReproducerBundle(for: requestInfo, bundlePath: bundlePath)
  }
}
