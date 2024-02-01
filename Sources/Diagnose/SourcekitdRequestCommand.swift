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
    let sourcekitd = try SourceKitDImpl.getOrCreate(dylibPath: try! AbsolutePath(validating: sourcekitdPath))
    let response = try await sourcekitd.run(requestYaml: requestString)

    switch response.error {
    case .requestFailed, .requestInvalid, .requestCancelled, .missingRequiredSymbol:
      throw ExitCode(1)
    case .connectionInterrupted:
      throw ExitCode(255)
    case nil:
      print(response.description)
    }
  }
}
