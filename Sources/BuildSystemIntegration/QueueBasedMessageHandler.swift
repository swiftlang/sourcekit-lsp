//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import SKLogging
import SKSupport
import SwiftExtensions

/// A `MessageHandler` that handles all messages on a serial queue.
///
/// This is a slightly simplified version of the message handling in `SourceKitLSPServer`, which does not set logging
/// scopes, because the build system messages should still be logged in the scope of the original LSP request that
/// triggered them.
protocol QueueBasedMessageHandler: MessageHandler {
  var messageHandlingQueue: AsyncQueue<Serial> { get }

  static var signpostLoggingCategory: String { get }

  func handleImpl(_ notification: some NotificationType) async

  func handleImpl<Request: RequestType>(_ requestAndReply: RequestAndReply<Request>) async
}

extension QueueBasedMessageHandler {
  /// Handle a notification without a reply.
  ///
  /// The method should return as soon as the notification has been sufficiently
  /// handled to avoid out-of-order requests, e.g. once the notification has
  /// been forwarded to clangd.
  package func handle(_ notification: some NotificationType) {
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: Self.signpostLoggingCategory)
      .makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("Notification", id: signpostID, "\(type(of: notification))")
    messageHandlingQueue.async {
      signposter.emitEvent("Start handling", id: signpostID)
      await self.handleImpl(notification)
      signposter.endInterval("Notification", state, "Done")
    }
  }

  /// Handle a request and (asynchronously) receive a reply.
  ///
  /// The method should return as soon as the request has been sufficiently
  /// handled to avoid out-of-order requests, e.g. once the corresponding
  /// request has been sent to sourcekitd. The actual semantic computation
  /// should occur after the method returns and report the result via `reply`.
  package func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) {
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: Self.signpostLoggingCategory)
      .makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("Request", id: signpostID, "\(Request.self)")

    messageHandlingQueue.async {
      signposter.emitEvent("Start handling", id: signpostID)
      await withTaskCancellationHandler {
        let startDate = Date()

        let requestAndReply = RequestAndReply(request) { result in
          reply(result)
          let endDate = Date()
          Task {
            switch result {
            case .success(let response):
              logger.log(
                """
                Succeeded (took \(endDate.timeIntervalSince(startDate) * 1000, privacy: .public)ms)
                \(Request.method, privacy: .public)
                \(response.forLogging)
                """
              )
            case .failure(let error):
              logger.log(
                """
                Failed (took \(endDate.timeIntervalSince(startDate) * 1000, privacy: .public)ms)
                \(Request.method, privacy: .public)(\(id, privacy: .public))
                \(error.forLogging, privacy: .private)
                """
              )
            }
          }
        }

        await self.handleImpl(requestAndReply)
        signposter.endInterval("Request", state, "Done")
      } onCancel: {
        signposter.emitEvent("Cancelled", id: signpostID)
      }
    }
  }
}
