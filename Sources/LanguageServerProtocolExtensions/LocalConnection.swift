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

import Dispatch
import Foundation
package import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKLogging
import SwiftExtensions

/// A connection between two message handlers in the same process.
///
/// You must call `start(handler:)` before sending any messages, and must call `close()` when finished to avoid a memory leak.
///
/// ```
/// let client: MessageHandler = ...
/// let server: MessageHandler = ...
/// let conn = LocalConnection()
/// conn.start(handler: server)
/// conn.send(...) // handled by server
/// conn.close()
/// ```
package final class LocalConnection: Connection, Sendable {
  private enum State {
    case ready, started, closed
  }

  /// A name of the endpoint for this connection, used for logging, e.g. `clangd`.
  private let name: String

  /// The queue guarding `_nextRequestID`.
  private let queue: DispatchQueue = DispatchQueue(label: "local-connection-queue")

  private let _nextRequestID = AtomicUInt32(initialValue: 0)

  /// - Important: Must only be accessed from `queue`
  nonisolated(unsafe) private var state: State = .ready

  /// - Important: Must only be accessed from `queue`
  nonisolated(unsafe) private var handler: MessageHandler? = nil

  package init(receiverName: String) {
    self.name = receiverName
  }

  package convenience init(receiverName: String, handler: MessageHandler) {
    self.init(receiverName: receiverName)
    self.start(handler: handler)
  }

  deinit {
    queue.sync {
      if state != .closed {
        closeAssumingOnQueue()
      }
    }
  }

  package func start(handler: MessageHandler) {
    queue.sync {
      precondition(state == .ready)
      state = .started
      self.handler = handler
    }
  }

  /// - Important: Must only be called from `queue`
  private func closeAssumingOnQueue() {
    dispatchPrecondition(condition: .onQueue(queue))
    precondition(state != .closed)
    handler = nil
    state = .closed
  }

  package func close() {
    queue.sync {
      closeAssumingOnQueue()
    }
  }

  public func nextRequestID() -> RequestID {
    return .string("sk-\(_nextRequestID.fetchAndIncrement())")
  }

  package func send<Notification: NotificationType>(_ notification: Notification) {
    logger.info(
      """
      Sending notification to \(self.name, privacy: .public)
      \(notification.forLogging)
      """
    )
    guard let handler = queue.sync(execute: { handler }) else {
      return
    }
    handler.handle(notification)
  }

  package func send<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) {
    logger.info(
      """
      Sending request to \(self.name, privacy: .public) (id: \(id, privacy: .public)):
      \(request.forLogging)
      """
    )

    guard let handler = queue.sync(execute: { handler }) else {
      logger.info(
        """
        Replying to request \(id, privacy: .public) with .serverCancelled because no handler is specified in \(self.name, privacy: .public)
        """
      )
      reply(.failure(.serverCancelled))
      return
    }

    precondition(self.state == .started)
    let startDate = Date()
    handler.handle(request, id: id) { result in
      switch result {
      case .success(let response):
        logger.info(
          """
          Received reply for request \(id, privacy: .public) from \(self.name, privacy: .public) \
          (took \(Date().timeIntervalSince(startDate) * 1000, privacy: .public)ms)
          \(Request.method, privacy: .public)
          \(response.forLogging)
          """
        )
      case .failure(let error):
        logger.error(
          """
          Received error for request \(id, privacy: .public) from \(self.name, privacy: .public) \
          (took \(Date().timeIntervalSince(startDate) * 1000, privacy: .public)ms)
          \(Request.method, privacy: .public)
          \(error.forLogging)
          """
        )
      }
      reply(result)
    }
  }
}
