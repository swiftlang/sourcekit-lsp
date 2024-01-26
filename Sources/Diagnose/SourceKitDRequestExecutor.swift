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

/// The different states in which a sourcektid request can finish.
enum SourceKitDRequestResult {
  /// The request succeeded.
  case success

  /// The request failed but did not crash.
  case error

  /// Running the request crashed
  case crashed
}

fileprivate extension String {
  init?(bytes: [UInt8], encoding: Encoding) {
    let data = bytes.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return Data()
      }
      return Data(bytes: baseAddress, count: buffer.count)
    }
    self.init(data: data, encoding: encoding)
  }
}

/// Runs `sourcekit-lsp run-sourcekitd-request` to check if a sourcekit-request crashes.
struct SourceKitRequestExecutor {
  /// The path to `sourcekitd.framework/sourcekitd`.
  private let sourcekitd: URL

  /// The file to which we write the JSON request that we want to run.
  private let temporarySourceFile: URL

  init(sourcekitd: URL) {
    self.sourcekitd = sourcekitd
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
      return .success
    case .terminated(code: 4):
      return .crashed
    default:
      return .error
    }
  }
}
