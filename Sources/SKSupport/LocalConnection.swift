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
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKLogging

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

  /// - Important: Must only be accessed from `queue`
  nonisolated(unsafe) private var _nextRequestID: Int = 0

  /// - Important: Must only be accessed from `queue`
  nonisolated(unsafe) private var state: State = .ready

  /// - Important: Must only be accessed from `queue`
  nonisolated(unsafe) private var handler: MessageHandler? = nil

  package init(name: String) {
    self.name = name
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

  func nextRequestID() -> RequestID {
    return queue.sync {
      _nextRequestID += 1
      return .number(_nextRequestID)
    }
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
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    let id = nextRequestID()

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
      return id
    }

    precondition(self.state == .started)
    handler.handle(request, id: id) { result in
      switch result {
      case .success(let response):
        logger.info(
          """
          Received reply for request \(id, privacy: .public) from \(self.name, privacy: .public)
          \(response.forLogging)
          """
        )
      case .failure(let error):
        logger.error(
          """
          Received error for request \(id, privacy: .public) from \(self.name, privacy: .public)
          \(error.forLogging)
          """
        )
      }
      reply(result)
    }

    return id
  }
}
