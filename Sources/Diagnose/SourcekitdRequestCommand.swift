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
import SourceKitD

import struct TSCBasic.AbsolutePath

public struct SourceKitdRequestCommand: AsyncParsableCommand {
  public static var configuration = CommandConfiguration(
    commandName: "run-sourcekitd-request",
    abstract: "Run a sourcekitd request and print its result",
    shouldDisplay: false
  )

  @Option(
    name: .customLong("sourcekitd"),
    help: "Path to sourcekitd.framework/sourcekitd"
  )
  var sourcekitdPath: String

  @Option(
    name: .customLong("request-file"),
    help: "Path to a JSON sourcekitd request"
  )
  var sourcekitdRequestPath: String

  public init() {}

  public func run() async throws {
    let requestString = try String(contentsOf: URL(fileURLWithPath: sourcekitdRequestPath))

    let sourcekitd = try SourceKitDImpl.getOrCreate(
      dylibPath: try! AbsolutePath(validating: sourcekitdPath)
    )

    let request = try requestString.cString(using: .utf8)?.withUnsafeBufferPointer { buffer in
      var error: UnsafeMutablePointer<CChar>?
      let req = sourcekitd.api.request_create_from_yaml(buffer.baseAddress, &error)
      if let error {
        throw ReductionError("Failed to parse sourcekitd request from JSON: \(String(cString: error))")
      }
      precondition(req != nil)
      return req
    }
    let response: SKDResponse = await withCheckedContinuation { continuation in
      var handle: sourcekitd_request_handle_t? = nil
      sourcekitd.api.send_request(request, &handle) { resp in
        continuation.resume(returning: SKDResponse(resp, sourcekitd: sourcekitd))
      }
    }

    switch response.error {
    case .requestFailed:
      throw ExitCode(1)
    case .requestInvalid:
      throw ExitCode(2)
    case .requestCancelled:
      throw ExitCode(3)
    case .connectionInterrupted:
      throw ExitCode(4)
    case .missingRequiredSymbol:
      throw ExitCode(5)
    case nil:
      return
    }
  }
}
