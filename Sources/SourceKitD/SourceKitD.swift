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

import SKLogging

#if compiler(>=6)
package import Csourcekitd
import Dispatch
package import Foundation
import SwiftExtensions
#else
import Csourcekitd
import Dispatch
import Foundation
import SwiftExtensions
#endif

fileprivate struct SourceKitDRequestHandle: Sendable {
  /// `nonisolated(unsafe)` is fine because we just use the handle as an opaque value.
  nonisolated(unsafe) let handle: sourcekitd_api_request_handle_t
}

package struct PluginPaths: Equatable, CustomLogStringConvertible {
  package let clientPlugin: URL
  package let servicePlugin: URL

  package init(clientPlugin: URL, servicePlugin: URL) {
    self.clientPlugin = clientPlugin
    self.servicePlugin = servicePlugin
  }

  package var description: String {
    "(client: \(clientPlugin), service: \(servicePlugin))"
  }

  var redactedDescription: String {
    "(client: \(clientPlugin.description.hashForLogging), service: \(servicePlugin.description.hashForLogging))"
  }
}

/// Access to sourcekitd API, taking care of initialization, shutdown, and notification handler
/// multiplexing.
///
/// *Users* of this protocol should not call the api functions `initialize`, `shutdown`, or
/// `set_notification_handler`, which are global state managed internally by this class.
///
/// *Implementors* are expected to handle initialization and shutdown, e.g. during `init` and
/// `deinit` or by wrapping an existing sourcekitd session that outlives this object.
package protocol SourceKitD: AnyObject, Sendable {
  /// The sourcekitd API functions.
  var api: sourcekitd_api_functions_t { get }

  /// General API for the SourceKit service and client framework, eg. for plugin initialization and to set up custom
  /// variant functions.
  ///
  /// This must not be referenced outside of `SwiftSourceKitPlugin`, `SwiftSourceKitPluginCommon`, or
  /// `SwiftSourceKitClientPlugin`.
  var pluginApi: sourcekitd_plugin_api_functions_t { get }

  /// The API with which the SourceKit plugin handles requests.
  ///
  /// This must not be referenced outside of `SwiftSourceKitPlugin`.
  var servicePluginApi: sourcekitd_service_plugin_api_functions_t { get }

  /// The API with which the SourceKit plugin communicates with the type-checker in-process.
  ///
  /// This must not be referenced outside of `SwiftSourceKitPlugin`.
  var ideApi: sourcekitd_ide_api_functions_t { get }

  /// Convenience for accessing known keys.
  var keys: sourcekitd_api_keys { get }

  /// Convenience for accessing known keys.
  var requests: sourcekitd_api_requests { get }

  /// Convenience for accessing known keys.
  var values: sourcekitd_api_values { get }

  /// Adds a new notification handler, which will be weakly referenced.
  func addNotificationHandler(_ handler: SKDNotificationHandler) async

  /// Removes a previously registered notification handler.
  func removeNotificationHandler(_ handler: SKDNotificationHandler) async

  /// Log the given request.
  ///
  /// This log call is issued during normal operation. It is acceptable for the logger to truncate the log message
  /// to achieve good performance.
  func log(request: SKDRequestDictionary)

  /// Log the given request and file contents, ensuring they do not get truncated.
  ///
  /// This log call is used when a request has crashed. In this case we want the log to contain the entire request to be
  /// able to reproduce it.
  func log(crashedRequest: SKDRequestDictionary, fileContents: String?)

  /// Log the given response.
  ///
  /// This log call is issued during normal operation. It is acceptable for the logger to truncate the log message
  /// to achieve good performance.
  func log(response: SKDResponse)

  /// Log that the given request has been cancelled.
  func logRequestCancellation(request: SKDRequestDictionary)
}

package enum SKDError: Error, Equatable {
  /// The service has crashed.
  case connectionInterrupted

  /// The request was unknown or had an invalid or missing parameter.
  case requestInvalid(String)

  /// The request failed.
  case requestFailed(String)

  /// The request was cancelled.
  case requestCancelled

  /// The request exceeded the maximum allowed duration.
  case timedOut

  /// Loading a required symbol from the sourcekitd library failed.
  case missingRequiredSymbol(String)
}

extension SourceKitD {
  // MARK: - Convenience API for requests.

  /// - Parameters:
  ///   - request: The request to send to sourcekitd.
  ///   - timeout: The maximum duration how long to wait for a response. If no response is returned within this time,
  ///     declare the request as having timed out.
  ///   - fileContents: The contents of the file that the request operates on. If sourcekitd crashes, the file contents
  ///     will be logged.
  package func send(
    _ request: SKDRequestDictionary,
    timeout: Duration,
    fileContents: String?
  ) async throws -> SKDResponseDictionary {
    log(request: request)

    let sourcekitdResponse = try await withTimeout(timeout) {
      return try await withCancellableCheckedThrowingContinuation { (continuation) -> SourceKitDRequestHandle? in
        var handle: sourcekitd_api_request_handle_t? = nil
        self.api.send_request(request.dict, &handle) { response in
          continuation.resume(returning: SKDResponse(response!, sourcekitd: self))
        }
        if let handle {
          return SourceKitDRequestHandle(handle: handle)
        }
        return nil
      } cancel: { (handle: SourceKitDRequestHandle?) in
        if let handle {
          self.logRequestCancellation(request: request)
          self.api.cancel_request(handle.handle)
        }
      }
    }

    log(response: sourcekitdResponse)

    guard let dict = sourcekitdResponse.value else {
      if sourcekitdResponse.error == .connectionInterrupted {
        log(crashedRequest: request, fileContents: fileContents)
      }
      if sourcekitdResponse.error == .timedOut && !Task.isCancelled {
        throw SKDError.timedOut
      }
      throw sourcekitdResponse.error!
    }

    return dict
  }
}

/// A sourcekitd notification handler in a class to allow it to be uniquely referenced.
package protocol SKDNotificationHandler: AnyObject, Sendable {
  func notification(_: SKDResponse) -> Void
}
