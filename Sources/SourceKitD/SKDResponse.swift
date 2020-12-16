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
#if canImport(Glibc)
import Glibc
#endif

public final class SKDResponse {
  public let response: sourcekitd_response_t?
  public let sourcekitd: SourceKitD

  public init(_ response: sourcekitd_response_t?, sourcekitd: SourceKitD) {
    self.response = response
    self.sourcekitd = sourcekitd
  }

  deinit {
    sourcekitd.api.response_dispose(response)
  }

  public var error: SKDError? {
    if !sourcekitd.api.response_is_error(response) {
      return nil
    }
    switch sourcekitd.api.response_error_get_kind(response) {
      case SOURCEKITD_ERROR_CONNECTION_INTERRUPTED: return .connectionInterrupted
      case SOURCEKITD_ERROR_REQUEST_INVALID: return .requestInvalid(description)
      case SOURCEKITD_ERROR_REQUEST_FAILED: return .requestFailed(description)
      case SOURCEKITD_ERROR_REQUEST_CANCELLED: return .requestCancelled
      default: return .requestFailed(description)
    }
  }

  public var value: SKDResponseDictionary? {
    if sourcekitd.api.response_is_error(response) {
      return nil
    }
    return SKDResponseDictionary(sourcekitd.api.response_get_value(response), response: self)
  }
}

extension SKDResponse: CustomStringConvertible {
  public var description: String {
    let ptr = sourcekitd.api.response_description_copy(response)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
