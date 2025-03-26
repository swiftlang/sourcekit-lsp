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
package import Foundation
import SKLogging
import SwiftExtensions

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
    let sourcekitdResponse = try await withTimeout(timeout) {
      return try await withCancellableCheckedThrowingContinuation { (continuation) -> SourceKitDRequestHandle? in
        logger.info(
          """
          Sending sourcekitd request:
          \(request.forLogging)
          """
        )
        var handle: sourcekitd_api_request_handle_t? = nil
        self.api.send_request(request.dict, &handle) { response in
          continuation.resume(returning: SKDResponse(response!, sourcekitd: self))
        }
        Task {
          await self.didSend(request: request)
        }
        if let handle {
          return SourceKitDRequestHandle(handle: handle)
        }
        return nil
      } cancel: { (handle: SourceKitDRequestHandle?) in
        if let handle {
          logger.info(
            """
            Cancelling sourcekitd request:
            \(request.forLogging)
            """
          )
          self.api.cancel_request(handle.handle)
        }
      }
    }

    logger.log(
      level: (sourcekitdResponse.error == nil || sourcekitdResponse.error == .requestCancelled) ? .debug : .error,
      """
      Received sourcekitd response:
      \(sourcekitdResponse.forLogging)
      """
    )

    guard let dict = sourcekitdResponse.value else {
      if sourcekitdResponse.error == .connectionInterrupted {
        let log = """
          Request:
          \(request.description)

          File contents:
          \(fileContents ?? "<nil>")
          """
        let chunks = splitLongMultilineMessage(message: log)
        for (index, chunk) in chunks.enumerated() {
          logger.fault(
            """
            sourcekitd crashed (\(index + 1)/\(chunks.count))
            \(chunk)
            """
          )
        }
      }
      if sourcekitdResponse.error == .requestCancelled && !Task.isCancelled {
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
