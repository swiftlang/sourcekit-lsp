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
public protocol Connection: AnyObject {

  /// Send a notification without a reply.
  func send<Notification>(_: Notification) where Notification: NotificationType

  /// Send a request and (asynchronously) receive a reply.
  func send<Request>(_: Request, queue: DispatchQueue, reply: @escaping (LSPResult<Request.Response>) -> Void) -> RequestID where Request: RequestType

  /// Send a request synchronously. **Use wisely**.
  func sendSync<Request>(_: Request) throws -> Request.Response where Request: RequestType
}

extension Connection {
  public func sendSync<Request>(_ request: Request) throws -> Request.Response where Request: RequestType {
    var result: LSPResult<Request.Response>? = nil
    let semaphore = DispatchSemaphore(value: 0)
    _ = send(request, queue: DispatchQueue.global()) { _result in
      result = _result
      semaphore.signal()
    }
    semaphore.wait()
    return try result!.get()
  }
}

/// An abstract message handler, such as a language server or client.
public protocol MessageHandler: AnyObject {

  /// Handle a notification without a reply.
  ///
  /// The method should return as soon as the notification has been sufficiently
  /// handled to avoid out-of-order requests, e.g. once the notification has
  /// been forwarded to clangd.
  func handle(_ params: some NotificationType, from clientID: ObjectIdentifier) async

  /// Handle a request and (asynchronously) receive a reply.
  ///
  /// The method should return as soon as the request has been sufficiently
  /// handled to avoid out-of-order requests, e.g. once the corresponding
  /// request has been sent to sourcekitd. The actual semantic computation
  /// should occur after the method returns and report the result via `reply`.
  func handle<Request: RequestType>(_ params: Request, id: RequestID, from clientID: ObjectIdentifier, reply: @escaping (LSPResult<Request.Response>) -> Void) async
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
public final class LocalConnection {

  enum State {
    case ready, started, closed
  }

  /// The queue guarding `_nextRequestID`.
  let queue: DispatchQueue = DispatchQueue(label: "local-connection-queue")

  /// The queue on which all messages (notifications, requests, responses) are
  /// handled.
  ///
  /// The queue is blocked until the message has been sufficiently handled to
  /// avoid out-of-order handling of messages. For sourcekitd, this means that
  /// a request has been sent to sourcekitd and for clangd, this means that we
  /// have forwarded the request to clangd.
  ///
  /// The actual semantic handling of the message happens off this queue.
  let messageHandlingQueue: AsyncQueue = AsyncQueue(.serial)

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
}

extension LocalConnection: Connection {
  public func send<Notification>(_ notification: Notification) where Notification: NotificationType {
    messageHandlingQueue.async {
      await self.handler?.handle(notification, from: ObjectIdentifier(self))
    }
  }

  public func send<Request: RequestType>(
    _ request: Request,
    queue: DispatchQueue,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    let id = nextRequestID()

    messageHandlingQueue.async {
      guard let handler = self.handler else {
        queue.async {
          reply(.failure(.serverCancelled))
        }
        return
      }

      precondition(self.state == .started)
      await handler.handle(request, id: id, from: ObjectIdentifier(self)) { result in
        queue.async {
          reply(result)
        }
      }
    }

    return id
  }
}
