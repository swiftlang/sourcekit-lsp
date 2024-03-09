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

/// The different states in which a sourcekitd request can finish.
@_spi(Testing)
public enum SourceKitDRequestResult {
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
@_spi(Testing)
public protocol SourceKitRequestExecutor {
  func run(request: RequestInfo) async throws -> SourceKitDRequestResult
}

/// Runs `sourcekit-lsp run-sourcekitd-request` to check if a sourcekit-request crashes.
class OutOfProcessSourceKitRequestExecutor: SourceKitRequestExecutor {
  /// The path to `sourcekitd.framework/sourcekitd`.
  private let sourcekitd: URL

  /// The file to which we write the reduce source file.
  private let temporarySourceFile: URL

  /// The file to which we write the YAML request that we want to run.
  private let temporaryRequestFile: URL

  /// If this predicate evaluates to true on the sourcekitd response, the request is
  /// considered to reproduce the issue.
  private let reproducerPredicate: NSPredicate?

  init(sourcekitd: URL, reproducerPredicate: NSPredicate?) {
    self.sourcekitd = sourcekitd
    self.reproducerPredicate = reproducerPredicate
    temporaryRequestFile = FileManager.default.temporaryDirectory.appendingPathComponent("request-\(UUID()).yml")
    temporarySourceFile = FileManager.default.temporaryDirectory.appendingPathComponent("recude-\(UUID()).swift")
  }

  deinit {
    try? FileManager.default.removeItem(at: temporaryRequestFile)
    try? FileManager.default.removeItem(at: temporarySourceFile)
  }

  func run(request: RequestInfo) async throws -> SourceKitDRequestResult {
    try request.fileContents.write(to: temporarySourceFile, atomically: true, encoding: .utf8)
    let requestString = try request.request(for: temporarySourceFile)
    try requestString.write(to: temporaryRequestFile, atomically: true, encoding: .utf8)

    let process = Process(
      arguments: [
        ProcessInfo.processInfo.arguments[0],
        "run-sourcekitd-request",
        "--sourcekitd",
        sourcekitd.path,
        "--request-file",
        temporaryRequestFile.path,
      ]
    )
    try process.launch()
    let result = try await process.waitUntilExit()
    switch result.exitStatus {
    case .terminated(code: 0):
      if let outputStr = try? String(bytes: result.output.get(), encoding: .utf8) {
        if let reproducerPredicate, reproducerPredicate.evaluate(with: outputStr) {
          return .reproducesIssue
        }
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
}
