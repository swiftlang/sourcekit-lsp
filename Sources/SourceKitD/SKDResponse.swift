//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Csourcekitd
import SKLogging

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#elseif canImport(Bionic)
import Bionic
#endif

package final class SKDResponse: Sendable {
  private nonisolated(unsafe) let response: sourcekitd_api_response_t
  let sourcekitd: SourceKitD

  /// Creates a new `SKDResponse` that exclusively manages the raw `sourcekitd_api_response_t`.
  ///
  /// - Important: When this `SKDResponse` object gets destroyed, it will dispose the response. It is thus illegal to
  ///   have two `SDKResponse` objects managing the same `sourcekitd_api_response_t`.
  package init(_ response: sourcekitd_api_response_t, sourcekitd: SourceKitD) {
    self.response = response
    self.sourcekitd = sourcekitd
  }

  deinit {
    sourcekitd.api.response_dispose(response)
  }

  package var error: SKDError? {
    if !sourcekitd.api.response_is_error(response) {
      return nil
    }
    switch sourcekitd.api.response_error_get_kind(response) {
    case SOURCEKITD_API_ERROR_CONNECTION_INTERRUPTED: return .connectionInterrupted
    case SOURCEKITD_API_ERROR_REQUEST_INVALID: return .requestInvalid(description)
    case SOURCEKITD_API_ERROR_REQUEST_FAILED: return .requestFailed(description)
    case SOURCEKITD_API_ERROR_REQUEST_CANCELLED: return .requestCancelled
    default: return .requestFailed(description)
    }
  }

  package var value: SKDResponseDictionary? {
    if sourcekitd.api.response_is_error(response) {
      return nil
    }
    return SKDResponseDictionary(sourcekitd.api.response_get_value(response), response: self)
  }
}

extension SKDResponse: CustomStringConvertible {
  package var description: String {
    let ptr = sourcekitd.api.response_description_copy(response)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}

extension SKDResponse: CustomLogStringConvertible {
  package var redactedDescription: String {
    // TODO: Implement a better redacted log that contains keys, number of
    // elements in an array but not the data itself.
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1598)
    return "<\(description.filter(\.isNewline).count) lines>"
  }
}
