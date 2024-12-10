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

#if compiler(>=6)
package import ArgumentParser
import Foundation
import LanguageServerProtocolExtensions
import ToolchainRegistry
import SwiftExtensions
import TSCExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import class TSCUtility.PercentProgressAnimation
#else
import ArgumentParser
import Foundation
import LanguageServerProtocolExtensions
import ToolchainRegistry
import SwiftExtensions
import TSCExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import class TSCUtility.PercentProgressAnimation
#endif

/// When diagnosis is started, a progress bar displayed on the terminal that shows how far the diagnose command has
/// progressed.
/// Can't be a member of `DiagnoseCommand` because then `DiagnoseCommand` is no longer codable, which it needs to be
/// to be a `AsyncParsableCommand`.
@MainActor
private var progressBar: PercentProgressAnimation? = nil

/// The last progress that was reported on the progress bar. This ensures that when the progress indicator uses the
/// `MultiLinePercentProgressAnimation` (eg. because stderr is redirected to a file) we don't emit status updates
/// without making any real progress.
@MainActor
private var lastProgress: (Int, String)? = nil

/// A component of the diagnostic bundle that's collected in independent stages.
fileprivate enum BundleComponent: String, CaseIterable, ExpressibleByArgument {
  case crashReports = "crash-reports"
  case logs = "logs"
  case swiftVersions = "swift-versions"
  case sourcekitdCrashes = "sourcekitd-crashes"
  case swiftFrontendCrashes = "swift-frontend-crashes"
}

package struct DiagnoseCommand: AsyncParsableCommand {
  package static let configuration: CommandConfiguration = CommandConfiguration(
    commandName: "diagnose",
    abstract: "Creates a bundle containing information that help diagnose issues with sourcekit-lsp"
  )

  @Option(
    name: .customLong("os-log-history"),
    help: "If no request file is passed, how many minutes of OS Log history should be scraped for a crash."
  )
  var osLogScrapeDuration: Int = 60

  @Option(
    name: .customLong("toolchain"),
    help: """
      The toolchain used to reduce the sourcekitd issue. \
      If not specified, the toolchain is found in the same way that sourcekit-lsp finds it
      """
  )
  var toolchainOverride: String?

  @Option(
    parsing: .upToNextOption,
    help: """
      A space separated list of components to include in the diagnostic bundle. Includes all components by default.

      Possible options are: \(BundleComponent.allCases.map(\.rawValue).joined(separator: ", "))
      """
  )
  private var components: [BundleComponent] = BundleComponent.allCases

  @Option(
    help: """
      The directory to which the diagnostic bundle should be written. No file or directory should exist at this path. \
      After sourcekit-lsp diagnose runs, a directory will exist at this path that contains the diagnostic bundle.
      """
  )
  var bundleOutputPath: String? = nil

  var toolchainRegistry: ToolchainRegistry {
    get throws {
      let installPath = Bundle.main.bundleURL
      return ToolchainRegistry(installPath: installPath)
    }
  }

  @MainActor
  var toolchain: Toolchain? {
    get async throws {
      if let toolchainOverride {
        return Toolchain(URL(fileURLWithPath: toolchainOverride))
      }
      return try await toolchainRegistry.default
    }
  }

  /// Request infos of crashes that should be diagnosed.
  func requestInfos() throws -> [(name: String, info: RequestInfo)] {
    #if canImport(OSLog)
    return try OSLogScraper(searchDuration: TimeInterval(osLogScrapeDuration * 60)).getCrashedRequests()
    #else
    throw GenericError("Reduction of sourcekitd crashes is not supported on platforms other than macOS")
    #endif
  }

  private var directoriesToScanForCrashReports: [String] {
    ["/Library/Logs/DiagnosticReports", "~/Library/Logs/DiagnosticReports"]
  }

  package init() {}

  @MainActor
  private func addSourcekitdCrashReproducer(toBundle bundlePath: URL) async throws {
    reportProgress(.reproducingSourcekitdCrash(progress: 0), message: "Trying to reduce recent sourcekitd crashes")
    for (name, requestInfo) in try requestInfos() {
      reportProgress(.reproducingSourcekitdCrash(progress: 0), message: "Reducing sourcekitd crash \(name)")
      do {
        try await reduce(
          requestInfo: requestInfo,
          toolchain: toolchain,
          bundlePath: bundlePath.appendingPathComponent("sourcekitd-crash"),
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

  @MainActor
  private func addSwiftFrontendCrashReproducer(toBundle bundlePath: URL) async throws {
    reportProgress(
      .reproducingSwiftFrontendCrash(progress: 0),
      message: "Trying to reduce recent Swift compiler crashes"
    )

    let crashInfos = SwiftFrontendCrashScraper(directoriesToScanForCrashReports: directoriesToScanForCrashReports)
      .findSwiftFrontendCrashes()
      .filter { $0.date > Date().addingTimeInterval(-TimeInterval(osLogScrapeDuration * 60)) }
      .sorted(by: { $0.date > $1.date })

    for crashInfo in crashInfos {
      let dateFormatter = DateFormatter()
      dateFormatter.timeZone = NSTimeZone.local
      dateFormatter.dateStyle = .none
      dateFormatter.timeStyle = .medium
      let progressMessagePrefix = "Reducing Swift compiler crash at \(dateFormatter.string(from: crashInfo.date))"

      reportProgress(.reproducingSwiftFrontendCrash(progress: 0), message: progressMessagePrefix)

      let toolchainPath = crashInfo.swiftFrontend
        .deletingLastPathComponent()
        .deletingLastPathComponent()

      guard let toolchain = Toolchain(toolchainPath),
        let sourcekitd = toolchain.sourcekitd
      else {
        continue
      }

      let executor = OutOfProcessSourceKitRequestExecutor(
        sourcekitd: sourcekitd,
        swiftFrontend: crashInfo.swiftFrontend,
        reproducerPredicate: nil
      )

      do {
        let reducedRequesInfo = try await reduceFrontendIssue(
          frontendArgs: crashInfo.frontendArgs,
          using: executor,
          progressUpdate: { (progress, message) in
            reportProgress(
              .reproducingSwiftFrontendCrash(progress: progress),
              message: "\(progressMessagePrefix): \(message)"
            )
          }
        )

        let bundleDirectory = bundlePath.appendingPathComponent("swift-frontend-crash")
        try makeReproducerBundle(for: reducedRequesInfo, toolchain: toolchain, bundlePath: bundleDirectory)

        // If reduce didn't throw, we have found a reproducer. Stop.
        // Looking further probably won't help because other crashes are likely the same cause.
        break
      } catch {
        // Reducing this request failed. Continue reducing the next one, maybe that one succeeds.
      }
    }
  }

  /// Execute body and if it throws, log the error.
  @MainActor
  private func orPrintError(_ body: @MainActor () async throws -> Void) async {
    do {
      try await body()
    } catch {
      print(error)
    }
  }

  @MainActor
  private func addOsLog(toBundle bundlePath: URL) async throws {
    #if os(macOS)
    reportProgress(.collectingLogMessages(progress: 0), message: "Collecting log messages")
    let outputFileUrl = bundlePath.appendingPathComponent("log.txt")
    guard FileManager.default.createFile(atPath: try outputFileUrl.filePath, contents: nil) else {
      throw GenericError("Failed to create log.txt")
    }
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
        "--signpost",
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

  @MainActor
  private func addNonDarwinLogs(toBundle bundlePath: URL) async throws {
    reportProgress(.collectingLogMessages(progress: 0), message: "Collecting log files")

    let destinationDir = bundlePath.appendingPathComponent("logs")
    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

    let logFileDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".sourcekit-lsp")
      .appendingPathComponent("logs")
    let enumerator = FileManager.default.enumerator(at: logFileDirectoryURL, includingPropertiesForKeys: nil)
    while let fileUrl = enumerator?.nextObject() as? URL {
      guard fileUrl.lastPathComponent.hasPrefix("sourcekit-lsp") else {
        continue
      }
      try? FileManager.default.copyItem(
        at: fileUrl,
        to: destinationDir.appendingPathComponent(fileUrl.lastPathComponent)
      )
    }
  }

  @MainActor
  private func addLogs(toBundle bundlePath: URL) async throws {
    try await addNonDarwinLogs(toBundle: bundlePath)
    try await addOsLog(toBundle: bundlePath)
  }

  @MainActor
  private func addCrashLogs(toBundle bundlePath: URL) throws {
    #if os(macOS)
    reportProgress(.collectingCrashReports, message: "Collecting crash reports")

    let destinationDir = bundlePath.appendingPathComponent("crashes")
    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

    let processesToIncludeCrashReportsOf = ["SourceKitService", "sourcekit-lsp", "swift-frontend"]

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

  @MainActor
  private func addSwiftVersion(toBundle bundlePath: URL) async throws {
    let outputFileUrl = bundlePath.appendingPathComponent("swift-versions.txt")
    guard FileManager.default.createFile(atPath: try outputFileUrl.filePath, contents: nil) else {
      throw GenericError("Failed to create file at \(outputFileUrl)")
    }
    let fileHandle = try FileHandle(forWritingTo: outputFileUrl)

    let toolchains = try await toolchainRegistry.toolchains

    for (index, toolchain) in toolchains.enumerated() {
      reportProgress(
        .collectingSwiftVersions(progress: Double(index) / Double(toolchains.count)),
        message: "Determining Swift version of \(toolchain.identifier)"
      )

      guard let swiftUrl = toolchain.swift else {
        continue
      }

      try fileHandle.write(contentsOf: "\(swiftUrl.filePath) --version\n".data(using: .utf8)!)
      let process = Process(
        arguments: [try swiftUrl.filePath, "--version"],
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

  @MainActor
  private func reportProgress(_ state: DiagnoseProgressState, message: String) {
    let progress: (step: Int, message: String) = (Int(state.progress * 100), message)
    if lastProgress == nil || progress != lastProgress! {
      progressBar?.update(step: Int(state.progress * 100), total: 100, text: message)
      lastProgress = progress
    }
  }

  @MainActor
  package func run() async throws {
    // IMPORTANT: When adding information to this message, also add it to the message displayed in VS Code
    // (captureDiagnostics.ts in the vscode-swift repository)
    print(
      """
      sourcekit-lsp diagnose collects information that helps the developers of sourcekit-lsp diagnose and fix issues.
      This information contains:
      - Crash logs from SourceKit
      - Log messages emitted by SourceKit
      - Versions of Swift installed on your system
      - If possible, a minimized project that caused SourceKit to crash
      - If possible, a minimized project that caused the Swift compiler to crash

      All information is collected locally.

      """
    )

    progressBar = PercentProgressAnimation(
      stream: stderrStreamConcurrencySafe,
      header: "Diagnosing sourcekit-lsp issues"
    )

    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.timeZone = NSTimeZone.local
    let date = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let bundlePath =
      if let bundleOutputPath = self.bundleOutputPath {
        URL(fileURLWithPath: bundleOutputPath)
      } else {
        FileManager.default.temporaryDirectory
          .appendingPathComponent("sourcekit-lsp-diagnose")
          .appendingPathComponent("sourcekit-lsp-diagnose-\(date)")
      }
    try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)

    if components.isEmpty || components.contains(.crashReports) {
      await orPrintError { try addCrashLogs(toBundle: bundlePath) }
    }
    if components.isEmpty || components.contains(.logs) {
      await orPrintError { try await addLogs(toBundle: bundlePath) }
    }
    if components.isEmpty || components.contains(.swiftVersions) {
      await orPrintError { try await addSwiftVersion(toBundle: bundlePath) }
    }
    if components.isEmpty || components.contains(.sourcekitdCrashes) {
      await orPrintError { try await addSourcekitdCrashReproducer(toBundle: bundlePath) }
    }
    if components.isEmpty || components.contains(.swiftFrontendCrashes) {
      await orPrintError { try await addSwiftFrontendCrashReproducer(toBundle: bundlePath) }
    }

    progressBar?.complete(success: true)

    print(
      """

      Bundle created.
      When filing an issue at https://github.com/swiftlang/sourcekit-lsp/issues/new,
      please attach the bundle located at
      \(try bundlePath.filePath)
      """
    )

    #if os(macOS)
    // Reveal the bundle in Finder on macOS.
    // Don't open the bundle in Finder if the user manually specified a log output path. In that case they are running
    // `sourcekit-lsp diagnose` as part of a larger logging script (like the Swift for VS Code extension) and the caller
    // is responsible for showing the diagnose bundle location to the user
    if self.bundleOutputPath == nil {
      do {
        _ = try await Process.run(arguments: ["open", "-R", bundlePath.filePath], workingDirectory: nil)
      } catch {
        // If revealing the bundle in Finder should fail, we don't care. We still printed the bundle path to stdout.
      }
    }
    #endif
  }

  @MainActor
  private func reduce(
    requestInfo: RequestInfo,
    toolchain: Toolchain?,
    bundlePath: URL,
    progressUpdate: (_ progress: Double, _ message: String) -> Void
  ) async throws {
    guard let toolchain else {
      throw GenericError("Unable to find a toolchain")
    }
    guard let sourcekitd = toolchain.sourcekitd else {
      throw GenericError("Unable to find sourcekitd.framework")
    }
    guard let swiftFrontend = toolchain.swiftFrontend else {
      throw GenericError("Unable to find swift-frontend")
    }

    let requestInfo = requestInfo
    let executor = OutOfProcessSourceKitRequestExecutor(
      sourcekitd: sourcekitd,
      swiftFrontend: swiftFrontend,
      reproducerPredicate: nil
    )

    let reducedRequesInfo = try await requestInfo.reduce(using: executor, progressUpdate: progressUpdate)

    try makeReproducerBundle(for: reducedRequesInfo, toolchain: toolchain, bundlePath: bundlePath)
  }
}

/// Describes the state that the diagnose command is in. This is used to compute a progress bar.
fileprivate enum DiagnoseProgressState: Comparable {
  case collectingCrashReports
  case collectingLogMessages(progress: Double)
  case collectingSwiftVersions(progress: Double)
  case reproducingSourcekitdCrash(progress: Double)
  case reproducingSwiftFrontendCrash(progress: Double)

  var allFinalStates: [DiagnoseProgressState] {
    return [
      .collectingCrashReports,
      .collectingLogMessages(progress: 1),
      .collectingSwiftVersions(progress: 1),
      .reproducingSourcekitdCrash(progress: 1),
      .reproducingSwiftFrontendCrash(progress: 1),
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
    case .reproducingSwiftFrontendCrash:
      return 60
    }
  }

  var progress: Double {
    let estimatedTotalDuration = allFinalStates.reduce(0, { $0 + $1.estimatedDuration })
    var elapsedEstimatedDuration = allFinalStates.filter { $0 < self }.reduce(0, { $0 + $1.estimatedDuration })
    switch self {
    case .collectingCrashReports: break
    case .collectingLogMessages(let progress), .collectingSwiftVersions(progress: let progress),
      .reproducingSourcekitdCrash(progress: let progress), .reproducingSwiftFrontendCrash(progress: let progress):
      elapsedEstimatedDuration += progress * self.estimatedDuration
    }
    return elapsedEstimatedDuration / estimatedTotalDuration
  }
}
