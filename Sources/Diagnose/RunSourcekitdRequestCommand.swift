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
import Csourcekitd
import Foundation
import SKUtilities
import SwiftExtensions
import SourceKitD
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#else
import ArgumentParser
import Csourcekitd
import Foundation
import SKUtilities
import SourceKitD
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#endif

package struct RunSourceKitdRequestCommand: AsyncParsableCommand {
  package static let configuration = CommandConfiguration(
    commandName: "run-sourcekitd-request",
    abstract: "Run a sourcekitd request and print its result"
  )

  @Option(
    name: .customLong("sourcekitd"),
    help: "Path to sourcekitd.framework/sourcekitd"
  )
  var sourcekitdPath: String?

  @Option(
    name: .customLong("request-file"),
    help:
      "Path to a JSON sourcekitd request. Multiple may be passed to run them in sequence on the same sourcekitd instance"
  )
  var sourcekitdRequestPaths: [String]

  @Option(help: "line:column override for key.offset")
  var position: String?

  package init() {}

  package func run() async throws {
    let sourcekitdPath =
      if let sourcekitdPath {
        URL(fileURLWithPath: sourcekitdPath)
      } else if let path = await ToolchainRegistry(installPath: Bundle.main.bundleURL).default?.sourcekitd {
        path
      } else {
        print("Did not find sourcekitd in the toolchain. Specify path to sourcekitd manually by passing --sourcekitd")
        throw ExitCode(1)
      }
    let sourcekitd = try await DynamicallyLoadedSourceKitD.getOrCreate(
      dylibPath: sourcekitdPath
    )

    var lastResponse: SKDResponse?

    for sourcekitdRequestPath in sourcekitdRequestPaths {
      var requestString = try String(contentsOf: URL(fileURLWithPath: sourcekitdRequestPath), encoding: .utf8)
      if let lineColumn = position?.split(separator: ":", maxSplits: 2).map({ Int($0) }),
        lineColumn.count == 2,
        let line = lineColumn[0],
        let column = lineColumn[1]
      {
        let requestInfo = try RequestInfo(request: requestString)

        let lineTable = LineTable(requestInfo.fileContents)
        let offset = lineTable.utf8OffsetOf(line: line - 1, utf8Column: column - 1)
        print("Adjusting request offset to \(offset)")
        requestString.replace(#/key.offset: [0-9]+/#, with: "key.offset: \(offset)")
      }

      let request = try requestString.cString(using: .utf8)!.withUnsafeBufferPointer { buffer in
        var error: UnsafeMutablePointer<CChar>?
        let req = sourcekitd.api.request_create_from_yaml(buffer.baseAddress!, &error)
        if let error {
          throw GenericError("Failed to parse sourcekitd request from YAML: \(String(cString: error))")
        }
        guard let req else {
          throw GenericError("Failed to parse request from YAML but did not produce error")
        }
        return req
      }
      let response = await withCheckedContinuation { continuation in
        var handle: sourcekitd_api_request_handle_t? = nil
        sourcekitd.api.send_request(request, &handle) { resp in
          continuation.resume(returning: SKDResponse(resp!, sourcekitd: sourcekitd))
        }
      }
      lastResponse = response

      print(response.description)
    }

    switch lastResponse?.error {
    case .requestFailed, .requestInvalid, .requestCancelled, .timedOut, .missingRequiredSymbol:
      throw ExitCode(1)
    case .connectionInterrupted:
      throw ExitCode(255)
    case nil:
      break
    }
  }
}
