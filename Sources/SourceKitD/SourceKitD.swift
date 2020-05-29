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

@_exported import Csourcekitd

import SKSupport
import LSPLogging
import TSCBasic
import Dispatch

/// A wrapper for accessing the API of a sourcekitd library loaded via `dlopen`.
public final class SourceKitD {

  /// The path to the sourcekitd dylib.
  public let path: AbsolutePath

  /// The handle to the dylib.
  let dylib: DLHandle

  /// The sourcekitd API functions.
  public let api: sourcekitd_functions_t

  /// Convenience for accessing known keys.
  public let keys: sourcekitd_keys

  /// Convenience for accessing known keys.
  public let requests: sourcekitd_requests

  /// Convenience for accessing known keys.
  public let values: sourcekitd_values

  public enum Error: Swift.Error {
    /// The service has crashed.
    case connectionInterrupted

    /// The request was unknown or had an invalid or missing parameter.
    case requestInvalid(String)

    /// The request failed.
    case requestFailed(String)

    /// The request was cancelled.
    case requestCancelled

    /// Loading a required symbol from the sourcekitd library failed.
    case missingRequiredSymbol(String)
  }

  public init(dylib path: AbsolutePath) throws {
    self.path = path
    #if os(Windows)
    self.dylib = try dlopen(path.pathString, mode: [])
    #else
    self.dylib = try dlopen(path.pathString, mode: [.lazy, .local, .first])
    #endif
    self.api = try sourcekitd_functions_t(self.dylib)
    self.keys = sourcekitd_keys(api: self.api)
    self.requests = sourcekitd_requests(api: self.api)
    self.values = sourcekitd_values(api: self.api)
  }

  deinit {
    // FIXME: is it safe to dlclose() sourcekitd? If so, do that here. For now, let the handle leak.
    dylib.leak()
  }
}

extension SourceKitD {

  // MARK: - Convenience API for requests.

  /// Send the given request and synchronously receive a reply dictionary (or error).
  public func sendSync(_ req: SKDRequestDictionary) throws -> SKDResponseDictionary {
    logAsync { _ in req.description }

    let resp = SKDResponse(api.send_request_sync(req.dict), sourcekitd: self)

    guard let dict = resp.value else {
      log(resp.description, level: .error)
      throw resp.error!
    }

    logAsync(level: .debug) { _ in dict.description }

    return dict
  }

  /// Send the given request and asynchronously receive a reply dictionary (or error) on the given queue.
  public func send(
    _ req: SKDRequestDictionary,
    _ queue: DispatchQueue,
    reply: @escaping (Result<SKDResponseDictionary, Error>) -> Void
  ) -> sourcekitd_request_handle_t? {
    logAsync { _ in req.description }

    var handle: sourcekitd_request_handle_t? = nil

    api.send_request(req.dict, &handle) { [weak self] _resp in
      guard let self = self else { return }

      let resp = SKDResponse(_resp, sourcekitd: self)

      guard let dict = resp.value else {
        log(resp.description, level: .error)
        queue.async {
         reply(.failure(resp.error!))
        }
        return
      }

      logAsync(level: .debug) { _ in dict.description }

      queue.async {
        reply(.success(dict))
      }
    }

    return handle
  }
}
