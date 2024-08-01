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

import Foundation
import SourceKitD

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

  /// The path to `swift-frontend`.
  private let swiftFrontend: URL

  /// The file to which we write the reduce source file.
  private let temporarySourceFile: URL

  /// The file to which we write the YAML request that we want to run.
  private let temporaryRequestFile: URL

  /// If this predicate evaluates to true on the sourcekitd response, the request is
  /// considered to reproduce the issue.
  private let reproducerPredicate: NSPredicate?

  package init(sourcekitd: URL, swiftFrontend: URL, reproducerPredicate: NSPredicate?) {
    self.sourcekitd = sourcekitd
    self.swiftFrontend = swiftFrontend
    self.reproducerPredicate = reproducerPredicate
    temporaryRequestFile = FileManager.default.temporaryDirectory.appendingPathComponent("request-\(UUID()).yml")
    temporarySourceFile = FileManager.default.temporaryDirectory.appendingPathComponent("recude-\(UUID()).swift")
  }

  deinit {
    try? FileManager.default.removeItem(at: temporaryRequestFile)
    try? FileManager.default.removeItem(at: temporarySourceFile)
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

    let arguments = request.compilerArgs.replacing(["$FILE"], with: [temporarySourceFile.path])

    let process = Process(arguments: [swiftFrontend.path] + arguments)
    try process.launch()
    let result = try await process.waitUntilExit()

    return requestResult(for: result)
  }

  package func runSourceKitD(request: RequestInfo) async throws -> SourceKitDRequestResult {
    try request.fileContents.write(to: temporarySourceFile, atomically: true, encoding: .utf8)
    let requestString = try request.request(for: temporarySourceFile)
    try requestString.write(to: temporaryRequestFile, atomically: true, encoding: .utf8)

    let process = Process(
      arguments: [
        ProcessInfo.processInfo.arguments[0],
        "debug",
        "run-sourcekitd-request",
        "--sourcekitd",
        sourcekitd.path,
        "--request-file",
        temporaryRequestFile.path,
      ]
    )
    try process.launch()
    let result = try await process.waitUntilExit()

    return requestResult(for: result)
  }
}
