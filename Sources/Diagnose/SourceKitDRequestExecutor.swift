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
enum SourceKitDRequestResult {
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

/// Runs `sourcekit-lsp run-sourcekitd-request` to check if a sourcekit-request crashes.
struct SourceKitRequestExecutor {
  /// The path to `sourcekitd.framework/sourcekitd`.
  private let sourcekitd: URL

  /// The file to which we write the JSON request that we want to run.
  private let temporarySourceFile: URL

  /// If this predicate evaluates to true on the sourcekitd response, the request is
  /// considered to reproduce the issue.
  private let reproducerPredicate: NSPredicate?

  init(sourcekitd: URL, reproducerPredicate: NSPredicate?) {
    self.sourcekitd = sourcekitd
    self.reproducerPredicate = reproducerPredicate
    temporarySourceFile = FileManager.default.temporaryDirectory.appendingPathComponent("request.json")
  }

  func run(request requestString: String) async throws -> SourceKitDRequestResult {
    try requestString.write(to: temporarySourceFile, atomically: true, encoding: .utf8)

    let process = Process(
      arguments: [
        ProcessInfo.processInfo.arguments[0],
        "run-sourcekitd-request",
        "--sourcekitd",
        sourcekitd.path,
        "--request-file",
        temporarySourceFile.path,
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
