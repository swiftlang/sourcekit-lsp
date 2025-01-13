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

#if compiler(>=6)
package import Csourcekitd
package import Foundation
import SKLogging
import SwiftExtensions
#else
import Csourcekitd
import Foundation
import SKLogging
import SwiftExtensions
#endif

extension sourcekitd_api_keys: @unchecked Sendable {}
extension sourcekitd_api_requests: @unchecked Sendable {}
extension sourcekitd_api_values: @unchecked Sendable {}

/// Wrapper for sourcekitd, taking care of initialization, shutdown, and notification handler
/// multiplexing.
///
/// Users of this class should not call the api functions `initialize`, `shutdown`, or
/// `set_notification_handler`, which are global state managed internally by this class.
package actor DynamicallyLoadedSourceKitD: SourceKitD {
  /// The path to the sourcekitd dylib.
  package let path: URL

  /// The handle to the dylib.
  let dylib: DLHandle

  /// The sourcekitd API functions.
  package let api: sourcekitd_api_functions_t

  /// Convenience for accessing known keys.
  package let keys: sourcekitd_api_keys

  /// Convenience for accessing known keys.
  package let requests: sourcekitd_api_requests

  /// Convenience for accessing known keys.
  package let values: sourcekitd_api_values

  private nonisolated let notificationHandlingQueue = AsyncQueue<Serial>()

  /// List of notification handlers that will be called for each notification.
  private var notificationHandlers: [WeakSKDNotificationHandler] = []

  package static func getOrCreate(dylibPath: URL) async throws -> SourceKitD {
    try await SourceKitDRegistry.shared
      .getOrAdd(dylibPath, create: { try DynamicallyLoadedSourceKitD(dylib: dylibPath) })
  }

  init(dylib path: URL) throws {
    self.path = path
    #if os(Windows)
    self.dylib = try dlopen(path.filePath, mode: [])
    #else
    self.dylib = try dlopen(path.filePath, mode: [.lazy, .local, .first])
    #endif
    self.api = try sourcekitd_api_functions_t(self.dylib)
    self.keys = sourcekitd_api_keys(api: self.api)
    self.requests = sourcekitd_api_requests(api: self.api)
    self.values = sourcekitd_api_values(api: self.api)

    self.api.initialize()
    self.api.set_notification_handler { [weak self] rawResponse in
      guard let self, let rawResponse else { return }
      let response = SKDResponse(rawResponse, sourcekitd: self)
      self.notificationHandlingQueue.async {
        let handlers = await self.notificationHandlers.compactMap(\.value)

        for handler in handlers {
          handler.notification(response)
        }
      }
    }
  }

  deinit {
    self.api.set_notification_handler(nil)
    self.api.shutdown()
    Task.detached(priority: .background) { [dylib, path] in
      orLog("Closing dylib \(path)") { try dylib.close() }
    }
  }

  /// Adds a new notification handler (referenced weakly).
  package func addNotificationHandler(_ handler: SKDNotificationHandler) {
    notificationHandlers.removeAll(where: { $0.value == nil })
    notificationHandlers.append(.init(handler))
  }

  /// Removes a previously registered notification handler.
  package func removeNotificationHandler(_ handler: SKDNotificationHandler) {
    notificationHandlers.removeAll(where: { $0.value == nil || $0.value === handler })
  }

  package nonisolated func log(request: SKDRequestDictionary) {
    logger.info(
      """
      Sending sourcekitd request:
      \(request.forLogging)
      """
    )
  }

  package nonisolated func log(response: SKDResponse) {
    logger.log(
      level: (response.error == nil || response.error == .requestCancelled) ? .debug : .error,
      """
      Received sourcekitd response:
      \(response.forLogging)
      """
    )
  }

  package nonisolated func log(crashedRequest req: SKDRequestDictionary, fileContents: String?) {
    let log = """
      Request:
      \(req.description)

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

  package nonisolated func logRequestCancellation(request: SKDRequestDictionary) {
    // We don't need to log which request has been cancelled because we can associate the cancellation log message with
    // the send message via the log
    logger.info(
      """
      Cancelling sourcekitd request:
      \(request.forLogging)
      """
    )
  }
}

struct WeakSKDNotificationHandler: Sendable {
  weak private(set) var value: SKDNotificationHandler?
  init(_ value: SKDNotificationHandler) {
    self.value = value
  }
}
