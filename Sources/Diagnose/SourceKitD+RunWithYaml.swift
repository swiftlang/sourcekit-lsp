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

import SourceKitD

extension SourceKitD {
  /// Parse the request from YAML and execute it.
  package func run(requestYaml: String) async throws -> SKDResponse {
    let request = try requestYaml.cString(using: .utf8)?.withUnsafeBufferPointer { buffer in
      var error: UnsafeMutablePointer<CChar>?
      let req = api.request_create_from_yaml(buffer.baseAddress!, &error)
      if let error {
        throw GenericError("Failed to parse sourcekitd request from YAML: \(String(cString: error))")
      }
      return req
    }
    return await withCheckedContinuation { continuation in
      var handle: sourcekitd_api_request_handle_t? = nil
      api.send_request(request!, &handle) { response in
        continuation.resume(returning: SKDResponse(response!, sourcekitd: self))
      }
    }
  }
}
