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
import SKSupport

/// An abstract connection, allow messages to be sent to a (potentially remote) `MessageHandler`.
public protocol Connection: AnyObject {

  /// Send a notification without a reply.
  func send<Notification>(_: Notification) where Notification: NotificationType

  /// Send a request and (asynchronously) receive a reply.
  func send<Request: RequestType>(
    _: Request,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID

  /// Send a request synchronously. **Use wisely**.
  func sendSync<Request>(_: Request) throws -> Request.Response where Request: RequestType
}

extension Connection {
  public func sendSync<Request>(_ request: Request) throws -> Request.Response where Request: RequestType {
    var result: LSPResult<Request.Response>? = nil
    let semaphore = DispatchSemaphore(value: 0)
    _ = send(request) { _result in
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
  func handle(_ params: some NotificationType, from clientID: ObjectIdentifier)

  /// Handle a request and (asynchronously) receive a reply.
  ///
  /// The method should return as soon as the request has been sufficiently
  /// handled to avoid out-of-order requests, e.g. once the corresponding
  /// request has been sent to sourcekitd. The actual semantic computation
  /// should occur after the method returns and report the result via `reply`.
  func handle<Request: RequestType>(
    _ params: Request,
    id: RequestID,
    from clientID: ObjectIdentifier,
    reply: @escaping (LSPResult<Request.Response>) -> Void
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
public final class LocalConnection {

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
}

extension LocalConnection: Connection {
  public func send<Notification>(_ notification: Notification) where Notification: NotificationType {
    self.handler?.handle(notification, from: ObjectIdentifier(self))
  }

  public func send<Request: RequestType>(
    _ request: Request,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    let id = nextRequestID()

    guard let handler = self.handler else {
      reply(.failure(.serverCancelled))
      return id
    }

    precondition(self.state == .started)
    handler.handle(request, id: id, from: ObjectIdentifier(self)) { result in
      reply(result)
    }

    return id
  }
}

extension Connection {
  /// Send the given request to the connection and await its result.
  ///
  /// This method automatically sends a `CancelRequestNotification` to the
  /// connection if the task it is executing in is being cancelled.
  ///
  /// - Warning: Because this message is `async`, it does not provide any ordering
  ///   guarantees. If you need to gurantee that messages are sent in-order
  ///   use the version with a completion handler.
  public func send<R: RequestType>(_ request: R) async throws -> R.Response {
    let requestIDWrapper = ThreadSafeBox<RequestID?>(initialValue: nil)

    @Sendable
    func sendCancelNotification() {
      /// Take the request ID out of the box. This ensures that we only send the
      /// cancel notification once in case the `Task.isCancelled` and the
      /// `onCancel` check race.
      if let requestID = requestIDWrapper.takeValue() {
        self.send(CancelRequestNotification(id: requestID))
      }
    }

    return try await withTaskCancellationHandler(operation: {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let requestID = self.send(request) { result in
          continuation.resume(with: result)
        }
        requestIDWrapper.value = requestID

        // Check if the task was cancelled. This ensures we send a
        // CancelNotification even if the task gets cancelled after we register
        // the cancellation handler but before we set the `requestID`.
        if Task.isCancelled {
          sendCancelNotification()
        }
      }
    }, onCancel: sendCancelNotification)
  }
}
