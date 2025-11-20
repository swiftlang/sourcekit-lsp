//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Csourcekitd
import SourceKitD

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

final class SKDResponse: CustomStringConvertible, Sendable {
  enum ErrorKind {
    case connectionInterrupted
    case invalid
    case failed
    case cancelled

    fileprivate var underlyingError: sourcekitd_api_error_t {
      switch self {
      case .connectionInterrupted: return SOURCEKITD_API_ERROR_CONNECTION_INTERRUPTED
      case .invalid: return SOURCEKITD_API_ERROR_REQUEST_INVALID
      case .failed: return SOURCEKITD_API_ERROR_REQUEST_FAILED
      case .cancelled: return SOURCEKITD_API_ERROR_REQUEST_CANCELLED
      }
    }
  }

  nonisolated(unsafe) let value: sourcekitd_api_response_t
  let sourcekitd: SourceKitD

  init(takingUnderlyingResponse value: sourcekitd_api_response_t, sourcekitd: SourceKitD) {
    self.value = value
    self.sourcekitd = sourcekitd
  }

  convenience init(error errorKind: ErrorKind, description: String, sourcekitd: SourceKitD) {
    let resp = sourcekitd.servicePluginApi.response_error_create(errorKind.underlyingError, description)!
    self.init(takingUnderlyingResponse: resp, sourcekitd: sourcekitd)
  }

  static func from(error: any Error, sourcekitd: SourceKitD) -> SKDResponse {
    if let error = error as? (any SourceKitPluginError) {
      return error.response(sourcekitd: sourcekitd)
    } else if error is CancellationError {
      return SKDResponse(error: .cancelled, description: "Request cancelled", sourcekitd: sourcekitd)
    } else {
      return SKDResponse(error: .failed, description: String(describing: error), sourcekitd: sourcekitd)
    }
  }

  deinit {
    sourcekitd.api.response_dispose(value)
  }

  public func underlyingValueRetained() -> sourcekitd_api_response_t {
    return sourcekitd.servicePluginApi.response_retain(value)
  }

  public var description: String {
    let cstr = sourcekitd.api.response_description_copy(value)!
    defer { free(cstr) }
    return String(cString: cstr)
  }
}
