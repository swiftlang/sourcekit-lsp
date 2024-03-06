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

/// When diagnosis is started, a progress bar displayed on the terminal that shows how far the diagnose command has
/// progressed.
/// Can't be a member of `DiagnoseCommand` because then `DiagnoseCommand` is no longer codable, which it needs to be
/// to be a `AsyncParsableCommand`.
private var progressBar: PercentProgressAnimation? = nil

public struct DiagnoseCommand: AsyncParsableCommand {
  public static var configuration: CommandConfiguration = CommandConfiguration(
    commandName: "diagnose",
    abstract: "Creates a bundle containing information that help diagnose issues with sourcekit-lsp"
  )

  @Option(
    name: .customLong("os-log-history"),
    help: "If no request file is passed, how many minutes of OS Log history should be scraped for a crash."
  )
  var osLogScrapeDuration: Int = 60

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

  /// Request infos of crashes that should be diagnosed.
  func requestInfos() throws -> [(name: String, info: RequestInfo)] {
    #if canImport(OSLog)
    return try OSLogScraper(searchDuration: TimeInterval(osLogScrapeDuration * 60)).getCrashedRequests()
    #else
    throw ReductionError("Reduction of sourcekitd crashes is not supported on platforms other than macOS")
    #endif
  }

  public init() {}

  private func addSourcekitdCrashReproducer(toBundle bundlePath: URL) async throws {
    reportProgress(.reproducingSourcekitdCrash(progress: 0), message: "Trying to reduce recent sourcekitd crashes")
    guard let sourcekitd = try await sourcekitd else {
      throw ReductionError("Unable to find sourcekitd.framework")
    }

    for (name, requestInfo) in try requestInfos() {
      reportProgress(.reproducingSourcekitdCrash(progress: 0), message: "Reducing sourcekitd crash \(name)")
      do {
        try await reduce(
          requestInfo: requestInfo,
          sourcekitd: sourcekitd,
          bundlePath: bundlePath.appendingPathComponent("reproducer"),
          progressUpdate: { (progress, message) in
            reportProgress(
              .reproducingSourcekitdCrash(progress: progress),
              message: "Reducing sourcekitd crash \(name): \(message)"
            )
          }
        )
        // If reduce didn't throw, we have found a reproducer. Stop.
        // Looking further probably won't help because other crashes are likely the same cause.
        break
      } catch {
        // Reducing this request failed. Continue reducing the next one, maybe that one succeeds.
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
    reportProgress(.collectingLogMessages(progress: 0), message: "Collecting log messages")
    let outputFileUrl = bundlePath.appendingPathComponent("log.txt")
    FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: outputFileUrl)
    var bytesCollected = 0
    // 50 MB is an average log size collected by sourcekit-lsp diagnose.
    // It's a good proxy to show some progress indication for the majority of the time.
    let expectedLogSize = 50_000_000
    let process = Process(
      arguments: [
        "/usr/bin/log",
        "show",
        "--predicate", #"subsystem = "org.swift.sourcekit-lsp" AND process = "sourcekit-lsp""#,
        "--info",
        "--debug",
      ],
      outputRedirection: .stream(
        stdout: { bytes in
          try? fileHandle.write(contentsOf: bytes)
          bytesCollected += bytes.count
          var progress = Double(bytesCollected) / Double(expectedLogSize)
          if progress > 1 {
            // The log is larger than we expected. Halt at 100%
            progress = 1
          }
          reportProgress(.collectingLogMessages(progress: progress), message: "Collecting log messages")
        },
        stderr: { _ in }
      )
    )
    try process.launch()
    try await process.waitUntilExit()
    #endif
  }

  private func addCrashLogs(toBundle bundlePath: URL) throws {
    #if os(macOS)
    reportProgress(.collectingCrashReports, message: "Collecting crash reports")

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
    let outputFileUrl = bundlePath.appendingPathComponent("swift-versions.txt")
    FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: outputFileUrl)

    let toolchains = try await toolchainRegistry.toolchains

    for (index, toolchain) in toolchains.enumerated() {
      reportProgress(
        .collectingSwiftVersions(progress: Double(index) / Double(toolchains.count)),
        message: "Determining Swift version of \(toolchain.identifier)"
      )

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

  private func reportProgress(_ state: DiagnoseProgressState, message: String) {
    progressBar?.update(step: Int(state.progress * 100), total: 100, text: message)
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

      """
    )

    progressBar = PercentProgressAnimation(stream: stderrStream, header: "Diagnosing sourcekit-lsp issues")

    let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let bundlePath = FileManager.default.temporaryDirectory
      .appendingPathComponent("sourcekitd-reproducer-\(date)")
    try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)

    await orPrintError { try addCrashLogs(toBundle: bundlePath) }
    await orPrintError { try await addOsLog(toBundle: bundlePath) }
    await orPrintError { try await addSwiftVersion(toBundle: bundlePath) }
    await orPrintError { try await addSourcekitdCrashReproducer(toBundle: bundlePath) }

    progressBar?.complete(success: true)

    print(
      """

      Bundle created. 
      When filing an issue at https://github.com/apple/sourcekit-lsp/issues/new, 
      please attach the bundle located at 
      \(bundlePath.path)
      """
    )

  }

  private func reduce(
    requestInfo: RequestInfo,
    sourcekitd: String,
    bundlePath: URL,
    progressUpdate: (_ progress: Double, _ message: String) -> Void
  ) async throws {
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

    // How much time of the reduction is expected to be spent reducing the source compared to command line argument
    // reduction.
    let sourceReductionPercentage = 0.7

    requestInfo = try await requestInfo.reduceInputFile(
      using: executor,
      progressUpdate: { progress, message in
        progressUpdate(progress * sourceReductionPercentage, message)
      }
    )
    requestInfo = try await requestInfo.reduceCommandLineArguments(
      using: executor,
      progressUpdate: { progress, message in
        progressUpdate(sourceReductionPercentage + progress * (1 - sourceReductionPercentage), message)
      }
    )

    try makeReproducerBundle(for: requestInfo, bundlePath: bundlePath)
  }
}

/// Describes the state that the diagnose command is in. This is used to compute a progress bar.
fileprivate enum DiagnoseProgressState: Comparable {
  case collectingCrashReports
  case collectingLogMessages(progress: Double)
  case collectingSwiftVersions(progress: Double)
  case reproducingSourcekitdCrash(progress: Double)

  var allFinalStates: [DiagnoseProgressState] {
    return [
      .collectingCrashReports,
      .collectingLogMessages(progress: 1),
      .collectingSwiftVersions(progress: 1),
      .reproducingSourcekitdCrash(progress: 1),
    ]
  }

  /// An estimate of how long this state takes in seconds.
  ///
  /// The actual values are never displayed. We use these values to allocate a portion of the overall progress to this
  /// state.
  var estimatedDuration: Double {
    switch self {
    case .collectingCrashReports:
      return 1
    case .collectingLogMessages:
      return 15
    case .collectingSwiftVersions:
      return 10
    case .reproducingSourcekitdCrash:
      return 60
    }
  }

  var progress: Double {
    let estimatedTotalDuration = allFinalStates.reduce(0, { $0 + $1.estimatedDuration })
    var elapsedEstimatedDuration = allFinalStates.filter { $0 < self }.reduce(0, { $0 + $1.estimatedDuration })
    switch self {
    case .collectingCrashReports: break
    case .collectingLogMessages(let progress), .collectingSwiftVersions(progress: let progress),
      .reproducingSourcekitdCrash(progress: let progress):
      elapsedEstimatedDuration += progress * self.estimatedDuration
    }
    return elapsedEstimatedDuration / estimatedTotalDuration
  }
}
