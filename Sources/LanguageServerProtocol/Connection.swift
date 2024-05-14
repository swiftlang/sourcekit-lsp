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

/// An abstract connection, allow messages to be sent to a (potentially remote) `MessageHandler`.
public protocol Connection: AnyObject, Sendable {

  /// Send a notification without a reply.
  func send(_ notification: some NotificationType)

  /// Send a request and (asynchronously) receive a reply.
  func send<Request: RequestType>(
    _ request: Request,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) -> RequestID
}

/// An abstract message handler, such as a language server or client.
public protocol MessageHandler: AnyObject, Sendable {

  /// Handle a notification without a reply.
  ///
  /// The method should return as soon as the notification has been sufficiently
  /// handled to avoid out-of-order requests, e.g. once the notification has
  /// been forwarded to clangd.
  func handle(_ notification: some NotificationType)

  /// Handle a request and (asynchronously) receive a reply.
  ///
  /// The method should return as soon as the request has been sufficiently
  /// handled to avoid out-of-order requests, e.g. once the corresponding
  /// request has been sent to sourcekitd. The actual semantic computation
  /// should occur after the method returns and report the result via `reply`.
  func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  )
}

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
///
/// - Note: Unchecked sendable conformance because shared state is guarded by `queue`.
public final class LocalConnection: Connection, @unchecked Sendable {

  enum State {
    case ready, started, closed
  }

  /// The queue guarding `_nextRequestID`.
  let queue: DispatchQueue = DispatchQueue(label: "local-connection-queue")

  var _nextRequestID: Int = 0

  var state: State = .ready

  var handler: MessageHandler? = nil

  public init() {}

  deinit {
    if state != .closed {
      close()
    }
  }

  public func start(handler: MessageHandler) {
    precondition(state == .ready)
    state = .started
    self.handler = handler
  }

  public func close() {
    precondition(state != .closed)
    handler = nil
    state = .closed
  }

  func nextRequestID() -> RequestID {
    return queue.sync {
      _nextRequestID += 1
      return .number(_nextRequestID)
    }
  }

  public func send<Notification>(_ notification: Notification) where Notification: NotificationType {
    self.handler?.handle(notification)
  }

  public func send<Request: RequestType>(
    _ request: Request,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    let id = nextRequestID()

    guard let handler = self.handler else {
      reply(.failure(.serverCancelled))
      return id
    }

    precondition(self.state == .started)
    handler.handle(request, id: id) { result in
      reply(result)
    }

    return id
  }
}
