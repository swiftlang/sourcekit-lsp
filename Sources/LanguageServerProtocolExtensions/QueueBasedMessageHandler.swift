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
import LanguageServerProtocolJSONRPC
import SKLogging

#if compiler(>=6)
package import LanguageServerProtocol
package import SwiftExtensions
#else
import LanguageServerProtocol
import SwiftExtensions
#endif

/// Side structure in which `QueueBasedMessageHandler` can keep track of active requests etc.
///
/// All of these could be requirements on `QueueBasedMessageHandler` but having them in a separate type means that
/// types conforming to `QueueBasedMessageHandler` only have to have a single member and it also ensures that these
/// fields are not accessible outside of the implementation of `QueueBasedMessageHandler`.
package actor QueueBasedMessageHandlerHelper {
  /// The category in which signposts for message handling should be logged.
  fileprivate let signpostLoggingCategory: String

  /// Whether a new logging scope should be created when handling a notification / request.
  private let createLoggingScope: Bool

  /// The queue on which we start and stop keeping track of cancellation.
  ///
  /// Having a queue for this ensures that we started keeping track of a
  /// request's task before handling any cancellation request for it.
  private let cancellationMessageHandlingQueue = AsyncQueue<Serial>()

  /// Notifications don't have an ID. This represents the next ID we can use to identify a notification.
  private let notificationIDForLogging = AtomicUInt32(initialValue: 1)

  /// The requests that we are currently handling.
  ///
  /// Used to cancel the tasks if the client requests cancellation.
  private var inProgressRequestsByID: [RequestID: Task<(), Never>] = [:]

  /// Up to 10 request IDs that have recently finished.
  ///
  /// This is only used so we don't log an error when receiving a `CancelRequestNotification` for a request that has
  /// just returned a response.
  private var recentlyFinishedRequests: [RequestID] = []

  package init(signpostLoggingCategory: String, createLoggingScope: Bool) {
    self.signpostLoggingCategory = signpostLoggingCategory
    self.createLoggingScope = createLoggingScope
  }

  /// Cancel the request with the given ID.
  ///
  /// Cancellation is performed automatically when a `$/cancelRequest` notification is received. This can be called to
  /// implicitly cancel requests based on some criteria.
  package nonisolated func cancelRequest(id: RequestID) {
    // Since the request is very cheap to execute and stops other requests
    // from performing more work, we execute it with a high priority.
    cancellationMessageHandlingQueue.async(priority: .high) {
      if let task = await self.inProgressRequestsByID[id] {
        task.cancel()
        return
      }
      if await !self.recentlyFinishedRequests.contains(id) {
        logger.error(
          "Cannot cancel request \(id, privacy: .public) because it hasn't been scheduled for execution yet"
        )
      }
    }
  }

  fileprivate nonisolated func setInProgressRequest(id: RequestID, request: some RequestType, task: Task<(), Never>?) {
    self.cancellationMessageHandlingQueue.async(priority: .background) {
      await self.setInProgressRequestImpl(id: id, request: request, task: task)
    }
  }

  private func setInProgressRequestImpl(id: RequestID, request: some RequestType, task: Task<(), Never>?) {
    self.inProgressRequestsByID[id] = task
    if task == nil {
      self.recentlyFinishedRequests.append(id)
      while self.recentlyFinishedRequests.count > 10 {
        self.recentlyFinishedRequests.removeFirst()
      }
    }
  }

  fileprivate nonisolated func withNotificationLoggingScopeIfNecessary(_ body: () -> Void) {
    guard createLoggingScope else {
      body()
      return
    }
    // Only use the last two digits of the notification ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running notifications.
    let notificationID = notificationIDForLogging.fetchAndIncrement()
    withLoggingScope("notification-\(notificationID % 100)") {
      body()
    }
  }

  fileprivate nonisolated func withRequestLoggingScopeIfNecessary(
    id: RequestID,
    _ body: @Sendable () async -> Void
  ) async {
    guard createLoggingScope else {
      await body()
      return
    }
    // Only use the last two digits of the request ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running requests.
    await withLoggingScope("request-\(id.numericValue % 100)") {
      await body()
    }
  }
}

package protocol QueueBasedMessageHandlerDependencyTracker: DependencyTracker {
  init(_ notification: some NotificationType)
  init(_ request: some RequestType)
}

/// A `MessageHandler` that handles all messages on an `AsyncQueue` and tracks dependencies between requests using
/// `DependencyTracker`, ensuring that requests which depend on each other are not executed out-of-order.
package protocol QueueBasedMessageHandler: MessageHandler {
  associatedtype DependencyTracker: QueueBasedMessageHandlerDependencyTracker

  /// The queue on which all messages (notifications, requests, responses) are
  /// handled.
  ///
  /// The queue is blocked until the message has been sufficiently handled to
  /// avoid out-of-order handling of messages. For sourcekitd, this means that
  /// a request has been sent to sourcekitd and for clangd, this means that we
  /// have forwarded the request to clangd.
  ///
  /// The actual semantic handling of the message happens off this queue.
  var messageHandlingQueue: AsyncQueue<DependencyTracker> { get }

  var messageHandlingHelper: QueueBasedMessageHandlerHelper { get }

  /// Called when a notification has been received but before it is being handled in `messageHandlingQueue`.
  ///
  /// Adopters can use this to implicitly cancel requests when a notification is received.
  func didReceive(notification: some NotificationType)

  /// Called when a request has been received but before it is being handled in `messageHandlingQueue`.
  ///
  /// Adopters can use this to implicitly cancel requests when a notification is received.
  func didReceive(request: some RequestType, id: RequestID)

  /// Perform the actual handling of `notification`.
  func handle(notification: some NotificationType) async

  /// Perform the actual handling of `request`.
  func handle<Request: RequestType>(
    request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) async
}

extension QueueBasedMessageHandler {
  package func didReceive(notification: some NotificationType) {}
  package func didReceive(request: some RequestType, id: RequestID) {}

  package func handle(_ notification: some NotificationType) {
    messageHandlingHelper.withNotificationLoggingScopeIfNecessary {
      // Request cancellation needs to be able to overtake any other message we
      // are currently handling. Ordering is not important here. We thus don't
      // need to execute it on `messageHandlingQueue`.
      if let notification = notification as? CancelRequestNotification {
        logger.log("Received cancel request notification: \(notification.forLogging)")
        self.messageHandlingHelper.cancelRequest(id: notification.id)
        return
      }
      self.didReceive(notification: notification)

      let signposter = Logger(
        subsystem: LoggingScope.subsystem,
        category: messageHandlingHelper.signpostLoggingCategory
      )
      .makeSignposter()
      let signpostID = signposter.makeSignpostID()
      let state = signposter.beginInterval("Notification", id: signpostID, "\(type(of: notification))")
      messageHandlingQueue.async(metadata: DependencyTracker(notification)) {
        signposter.emitEvent("Start handling", id: signpostID)
        await self.handle(notification: notification)
        signposter.endInterval("Notification", state, "Done")
      }
    }
  }

  package func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) {
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: messageHandlingHelper.signpostLoggingCategory)
      .makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("Request", id: signpostID, "\(Request.self)")

    self.didReceive(request: request, id: id)

    let task = messageHandlingQueue.async(metadata: DependencyTracker(request)) {
      signposter.emitEvent("Start handling", id: signpostID)
      await self.messageHandlingHelper.withRequestLoggingScopeIfNecessary(id: id) {
        await withTaskCancellationHandler {
          await self.handle(request: request, id: id, reply: reply)
          signposter.endInterval("Request", state, "Done")
        } onCancel: {
          signposter.emitEvent("Cancelled", id: signpostID)
        }
      }
      // We have handled the request and can't cancel it anymore.
      // Stop keeping track of it to free the memory.
      self.messageHandlingHelper.setInProgressRequest(id: id, request: request, task: nil)
    }
    // Keep track of the ID -> Task management with low priority. Once we cancel
    // a request, the cancellation task runs with a high priority and depends on
    // this task, which will elevate this task's priority.
    self.messageHandlingHelper.setInProgressRequest(id: id, request: request, task: task)
  }
}

fileprivate extension RequestID {
  /// Returns a numeric value for this request ID.
  ///
  /// For request IDs that are numbers, this is straightforward. For string-based request IDs, this uses a hash to
  /// convert the string into a number.
  var numericValue: Int {
    switch self {
    case .number(let number): return number
    case .string(let string): return Int(string) ?? abs(string.hashValue)
    }
  }
}
