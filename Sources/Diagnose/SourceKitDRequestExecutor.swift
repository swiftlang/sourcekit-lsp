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
package import SourceKitD
import SwiftExtensions
import TSCExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import struct TSCBasic.ProcessResult

/// The different states in which a sourcekitd request can finish.
package enum SourceKitDRequestResult: Sendable {
  /// The request succeeded.
  case success(response: String)

  /// The request failed but did not crash.
  case error

  /// Running the request reproduces the issue that should be reduced.
  case reproducesIssue
}

fileprivate extension String {
  init?(bytes: [UInt8], encoding: Encoding) {
    self = bytes.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return ""
      }
      let data = Data(bytes: baseAddress, count: buffer.count)
      return String(data: data, encoding: encoding)!
    }

  }
}

/// An executor that can run a sourcekitd request and indicate whether the request reprodes a specified issue.
package protocol SourceKitRequestExecutor {
  @MainActor func runSourceKitD(request: RequestInfo) async throws -> SourceKitDRequestResult
  @MainActor func runSwiftFrontend(request: RequestInfo) async throws -> SourceKitDRequestResult
}

extension SourceKitRequestExecutor {
  @MainActor
  func run(request: RequestInfo) async throws -> SourceKitDRequestResult {
    if request.requestTemplate == RequestInfo.fakeRequestTemplateForFrontendIssues {
      return try await runSwiftFrontend(request: request)
    } else {
      return try await runSourceKitD(request: request)
    }
  }
}

/// Runs `sourcekit-lsp run-sourcekitd-request` to check if a sourcekit-request crashes.
package class OutOfProcessSourceKitRequestExecutor: SourceKitRequestExecutor {
  /// The path to `sourcekitd.framework/sourcekitd`.
  private let sourcekitd: URL
  private let pluginPaths: PluginPaths?

  /// The path to `swift-frontend`.
  private let swiftFrontend: URL

  private let temporaryDirectory: URL

  /// The file to which we write the reduce source file.
  private var temporarySourceFile: URL {
    temporaryDirectory.appending(component: "reduce.swift")
  }

  /// If this predicate evaluates to true on the sourcekitd response, the request is
  /// considered to reproduce the issue.
  private let reproducerPredicate: NSPredicate?

  package init(sourcekitd: URL, pluginPaths: PluginPaths?, swiftFrontend: URL, reproducerPredicate: NSPredicate?) {
    self.sourcekitd = sourcekitd
    self.pluginPaths = pluginPaths
    self.swiftFrontend = swiftFrontend
    self.reproducerPredicate = reproducerPredicate
    temporaryDirectory = FileManager.default.temporaryDirectory.appending(component: "sourcekitd-execute-\(UUID())")
    try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  /// The `SourceKitDRequestResult` for the given process result, evaluating the reproducer predicate, if it was
  /// specified.
  private func requestResult(for result: ProcessResult) -> SourceKitDRequestResult {
    if let reproducerPredicate {
      if let outputStr = try? String(bytes: result.output.get(), encoding: .utf8),
        let stderrStr = try? String(bytes: result.stderrOutput.get(), encoding: .utf8)
      {
        let exitCode: Int32? =
          switch result.exitStatus {
          case .terminated(code: let exitCode): exitCode
          default: nil
          }

        let dict: [String: Any] = [
          "stdout": outputStr,
          "stderr": stderrStr,
          "exitCode": exitCode as Any,
        ]

        if reproducerPredicate.evaluate(with: dict) {
          return .reproducesIssue
        } else {
          return .error
        }
      } else {
        return .error
      }
    }

    switch result.exitStatus {
    case .terminated(code: 0):
      if let outputStr = try? String(bytes: result.output.get(), encoding: .utf8) {
        return .success(response: outputStr)
      } else {
        return .error
      }
    case .terminated(code: 1):
      // The request failed but did not crash. It doesn't reproduce the issue.
      return .error
    default:
      // Exited with a non-zero and non-one exit code. Looks like it crashed, so reproduces a crasher.
      return .reproducesIssue
    }
  }

  package func runSwiftFrontend(request: RequestInfo) async throws -> SourceKitDRequestResult {
    try request.fileContents.write(to: temporarySourceFile, atomically: true, encoding: .utf8)

    let arguments = request.compilerArgs.replacing(["$FILE"], with: [try temporarySourceFile.filePath])

    let process = Process(arguments: [try swiftFrontend.filePath] + arguments)
    try process.launch()
    let result = try await process.waitUntilExit()

    return requestResult(for: result)
  }

  package func runSourceKitD(request: RequestInfo) async throws -> SourceKitDRequestResult {
    var arguments = [
      ProcessInfo.processInfo.arguments[0],
      "debug",
      "run-sourcekitd-request",
      "--sourcekitd",
      try sourcekitd.filePath,
    ]
    if let pluginPaths {
      arguments += [
        "--sourcekit-plugin-path",
        try pluginPaths.servicePlugin.filePath,
        "--sourcekit-client-plugin-path",
        try pluginPaths.clientPlugin.filePath,
      ]
    }

    try request.fileContents.write(to: temporarySourceFile, atomically: true, encoding: .utf8)
    let requestStrings = try request.requests(for: temporarySourceFile)
    for (index, requestString) in requestStrings.enumerated() {
      let temporaryRequestFile = temporaryDirectory.appending(component: "request-\(index).yml")
      try requestString.write(
        to: temporaryRequestFile,
        atomically: true,
        encoding: .utf8
      )
      arguments += [
        "--request-file",
        try temporaryRequestFile.filePath,
      ]
    }

    let result = try await Process.run(arguments: arguments, workingDirectory: nil)
    return requestResult(for: result)
  }
}
