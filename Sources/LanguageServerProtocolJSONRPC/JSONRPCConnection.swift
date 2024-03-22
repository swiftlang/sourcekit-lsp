//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import Foundation
import LSPLogging
import LanguageServerProtocol

#if canImport(CDispatch)
import struct CDispatch.dispatch_fd_t
#endif

/// A connection between a message handler (e.g. language server) in the same process as the connection object and a remote message handler (e.g. language client) that may run in another process using JSON RPC messages sent over a pair of in/out file descriptors.
///
/// For example, inside a language server, the `JSONRPCConnection` takes the language service implementation as its `receiveHandler` and itself provides the client connection for sending notifications and callbacks.
public final class JSONRPCConnection: Connection {

  /// A name of the endpoint for this connection, used for logging, e.g. `clangd`.
  private let name: String

  /// The message handler that handles requests and notifications sent through this connection.
  ///
  /// Access to this must be be guaranteed to be sequential to avoid data races. Currently, all access are
  ///  - `init`: Reference to `JSONRPCConnection` trivially can't have escaped to other isolation domains yet.
  ///  - `start`: Is required to be call in the same serial code region as the initializer, so
  ///    `JSONRPCConnection` can't have escaped to other isolation domains yet.
  ///  - `deinit`: Can also only trivially be called once.
  nonisolated(unsafe) private var receiveHandler: MessageHandler?

  /// The queue on which we read the data
  private let queue: DispatchQueue = DispatchQueue(label: "jsonrpc-queue", qos: .userInitiated)

  /// The queue on which we send data.
  private let sendQueue: DispatchQueue = DispatchQueue(label: "jsonrpc-send-queue", qos: .userInitiated)

  private let receiveIO: DispatchIO
  private let sendIO: DispatchIO
  private let messageRegistry: MessageRegistry

  enum State {
    case created, running, closed
  }

  /// Current state of the connection, used to ensure correct usage.
  ///
  /// Access to this must be be guaranteed to be sequential to avoid data races. Currently, all access are
  ///  - `init`: Reference to `JSONRPCConnection` trivially can't have escaped to other isolation domains yet.
  ///  - `start`: Is required to be called in the same serial region as the initializer, so
  ///    `JSONRPCConnection` can't have escaped to other isolation domains yet.
  ///  - `_close`: Synchronized on `queue`.
  ///  - `readyToSend`: Synchronized on `queue`.
  ///  - `deinit`: Can also only trivially be called once.
  private nonisolated(unsafe) var state: State

  /// Buffer of received bytes that haven't been parsed.
  ///
  /// Access to this must be be guaranteed to be sequential to avoid data races. Currently, all access are
  ///  - The `receiveIO` handler: This is synchronized on `queue`.
  ///  - `requestBufferIsEmpty`: Also synchronized on `queue`.
  private nonisolated(unsafe) var requestBuffer: [UInt8] = []

  @_spi(Testing)
  public var requestBufferIsEmpty: Bool {
    queue.sync {
      requestBuffer.isEmpty
    }
  }

  /// An integer that hasn't been used for a request ID yet.
  ///
  /// Access to this must be be guaranteed to be sequential to avoid data races. Currently, all access are
  ///  - `nextRequestID()`: This is synchronized on `queue`.
  private nonisolated(unsafe) var nextRequestIDStorage: Int = 0

  struct OutstandingRequest: Sendable {
    var responseType: ResponseType.Type
    var replyHandler: @Sendable (LSPResult<Any>) -> Void
  }

  /// The set of currently outstanding outgoing requests along with information about how to decode and handle their
  /// responses.
  ///
  /// All accesses to `outstandingRequests` must be on `queue` to avoid race conditions.
  private nonisolated(unsafe) var outstandingRequests: [RequestID: OutstandingRequest] = [:]

  /// A handler that will be called asynchronously when the connection is being
  /// closed.
  ///
  /// There are no race conditions to `closeHandler` because it is only set from `start`, which is required to be called
  /// in the same serial code region domain as the initializer, so it's serial and the `JSONRPCConnection` can't
  /// have escaped to other isolation domains yet.
  private nonisolated(unsafe) var closeHandler: (@Sendable () async -> Void)? = nil

  /// - Important: `start` must be called before sending any data over the `JSONRPCConnection`.
  public init(
    name: String,
    protocol messageRegistry: MessageRegistry,
    inFD: FileHandle,
    outFD: FileHandle
  ) {
    self.name = name
    self.receiveHandler = nil
    #if os(Linux) || os(Android)
    // We receive a `SIGPIPE` if we write to a pipe that points to a crashed process. This in particular happens if the
    // target of a `JSONRPCConnection` has crashed and we try to send it a message.
    // On Darwin, `DispatchIO` ignores `SIGPIPE` for the pipes handled by it, but that features is not available on Linux.
    // Instead, globally ignore `SIGPIPE` on Linux to prevent us from crashing if the `JSONRPCConnection`'s target crashes.
    globallyDisableSigpipe()
    #endif
    state = .created
    self.messageRegistry = messageRegistry

    let ioGroup = DispatchGroup()

    #if os(Windows)
    let rawInFD = dispatch_fd_t(bitPattern: inFD._handle)
    #else
    let rawInFD = inFD.fileDescriptor
    #endif

    ioGroup.enter()
    receiveIO = DispatchIO(
      type: .stream,
      fileDescriptor: rawInFD,
      queue: queue,
      cleanupHandler: { (error: Int32) in
        if error != 0 {
          logger.error("IO error \(error)")
        }
        ioGroup.leave()
      }
    )

    #if os(Windows)
    let rawOutFD = dispatch_fd_t(bitPattern: outFD._handle)
    #else
    let rawOutFD = outFD.fileDescriptor
    #endif

    ioGroup.enter()
    sendIO = DispatchIO(
      type: .stream,
      fileDescriptor: rawOutFD,
      queue: sendQueue,
      cleanupHandler: { (error: Int32) in
        if error != 0 {
          logger.error("IO error \(error)")
        }
        ioGroup.leave()
      }
    )

    ioGroup.notify(queue: queue) { [weak self] in
      guard let self = self else { return }
      Task {
        await self.closeHandler?()
        self.receiveHandler = nil  // break retain cycle
      }
    }

    // We cannot assume the client will send us bytes in packets of any particular size, so set the lower limit to 1.
    receiveIO.setLimit(lowWater: 1)
    receiveIO.setLimit(highWater: Int.max)

    sendIO.setLimit(lowWater: 1)
    sendIO.setLimit(highWater: Int.max)
  }

  deinit {
    assert(state == .closed)
  }

  /// Start processing `inFD` and send messages to `receiveHandler`.
  ///
  /// - parameter receiveHandler: The message handler to invoke for requests received on the `inFD`.
  ///
  /// - Important: `start` must be called before sending any data over the `JSONRPCConnection`.
  public func start(receiveHandler: MessageHandler, closeHandler: @escaping @Sendable () async -> Void = {}) {
    queue.sync {
      precondition(state == .created)
      state = .running
      self.receiveHandler = receiveHandler
      self.closeHandler = closeHandler

      receiveIO.read(offset: 0, length: Int.max, queue: queue) { done, data, errorCode in
        guard errorCode == 0 else {
          #if !os(Windows)
          if errorCode != POSIXError.ECANCELED.rawValue {
            logger.error("IO error reading \(errorCode)")
          }
          #endif
          if done { self.closeAssumingOnQueue() }
          return
        }

        if done {
          self.closeAssumingOnQueue()
          return
        }

        guard let data = data, !data.isEmpty else {
          return
        }

        // Parse and handle any messages in `buffer + data`, leaving any remaining unparsed bytes in `buffer`.
        if self.requestBuffer.isEmpty {
          data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
            let rest = self.parseAndHandleMessages(from: UnsafeBufferPointer(start: pointer, count: data.count))
            self.requestBuffer.append(contentsOf: rest)
          }
        } else {
          self.requestBuffer.append(contentsOf: data)
          var unused = 0
          self.requestBuffer.withUnsafeBufferPointer { buffer in
            let rest = self.parseAndHandleMessages(from: buffer)
            unused = rest.count
          }
          self.requestBuffer.removeFirst(self.requestBuffer.count - unused)
        }
      }
    }
  }

  /// Whether we can send messages in the current state.
  ///
  /// - parameter shouldLog: Whether to log an info message if not ready.
  ///
  /// - Important: Must be called on `queue`. Note that the state might change as soon as execution leaves `queue`.
  func readyToSend(shouldLog: Bool = true) -> Bool {
    dispatchPrecondition(condition: .onQueue(queue))
    precondition(state != .created, "tried to send message before calling start(messageHandler:)")
    let ready = state == .running
    if shouldLog && !ready {
      logger.error("ignoring message; state = \(String(reflecting: self.state), privacy: .public)")
    }
    return ready
  }

  /// Parse and handle all messages in `bytes`, returning a slice containing any remaining incomplete data.
  ///
  /// - Important: Must be called on `queue`
  func parseAndHandleMessages(from bytes: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8>.SubSequence {
    dispatchPrecondition(condition: .onQueue(queue))
    let decoder = JSONDecoder()

    // Set message registry to use for model decoding.
    decoder.userInfo[.messageRegistryKey] = messageRegistry

    // Setup callback for response type.
    decoder.userInfo[.responseTypeCallbackKey] =
      { id in
        guard let outstanding = self.outstandingRequests[id] else {
          logger.error("Unknown request for \(id, privacy: .public)")
          return nil
        }
        return outstanding.responseType
      } as JSONRPCMessage.ResponseTypeCallback

    var bytes = bytes[...]

    MESSAGE_LOOP: while true {
      do {
        guard let ((messageBytes, _), rest) = try bytes.jsonrpcSplitMessage() else {
          return bytes
        }
        bytes = rest

        let pointer = UnsafeMutableRawPointer(mutating: UnsafeBufferPointer(rebasing: messageBytes).baseAddress!)
        let message = try decoder.decode(
          JSONRPCMessage.self,
          from: Data(bytesNoCopy: pointer, count: messageBytes.count, deallocator: .none)
        )

        handle(message)
      } catch let error as MessageDecodingError {
        switch error.messageKind {
        case .request:
          if let id = error.id {
            queue.async {
              self.send(.errorResponse(ResponseError(error), id: id))
            }
            continue MESSAGE_LOOP
          }
        case .response:
          if let id = error.id {
            if let outstanding = self.outstandingRequests.removeValue(forKey: id) {
              outstanding.replyHandler(.failure(ResponseError(error)))
            } else {
              logger.error("error in response to unknown request \(id, privacy: .public) \(error.forLogging)")
            }
            continue MESSAGE_LOOP
          }
        case .notification:
          if error.code == .methodNotFound {
            logger.error("ignoring unknown notification \(error.forLogging)")
            continue MESSAGE_LOOP
          }
        case .unknown:
          break
        }
        // FIXME: graceful shutdown?
        fatalError("fatal error encountered decoding message \(error)")
      } catch {
        // FIXME: graceful shutdown?
        fatalError("fatal error encountered decoding message \(error)")
      }
    }
  }

  /// Handle a single message by dispatching it to `receiveHandler` or an appropriate reply handler.
  ///
  /// - Important: Must be called on `queue`
  func handle(_ message: JSONRPCMessage) {
    dispatchPrecondition(condition: .onQueue(queue))
    switch message {
    case .notification(let notification):
      notification._handle(self.receiveHandler!)
    case .request(let request, id: let id):
      request._handle(self.receiveHandler!, id: id) { (response, id) in
        self.sendReply(response, id: id)
      }
    case .response(let response, id: let id):
      guard let outstanding = outstandingRequests.removeValue(forKey: id) else {
        logger.error("No outstanding requests for response ID \(id, privacy: .public)")
        return
      }
      outstanding.replyHandler(.success(response))
    case .errorResponse(let error, id: let id):
      guard let id = id else {
        logger.error("Received error response for unknown request: \(error.forLogging)")
        return
      }
      guard let outstanding = outstandingRequests.removeValue(forKey: id) else {
        logger.error("No outstanding requests for error response ID \(id, privacy: .public)")
        return
      }
      outstanding.replyHandler(.failure(error))
    }
  }

  /// Send the raw data to the receiving end of this connection.
  ///
  /// If an unrecoverable error occurred on the channel's file descriptor, the connection gets closed.
  ///
  /// - Important: Must be called on `queue`
  private func send(data dispatchData: DispatchData) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard readyToSend() else { return }

    sendIO.write(offset: 0, data: dispatchData, queue: sendQueue) { [weak self] done, _, errorCode in
      if errorCode != 0 {
        logger.error("IO error sending message \(errorCode)")
        if done, let self {
          // An unrecoverable error occurs on the channel’s file descriptor.
          // Close the connection.
          self.queue.async {
            self.closeAssumingOnQueue()
          }
        }
      }
    }
  }

  /// Wrapper of `send(data:)` that automatically switches to `queue`.
  ///
  /// This should only be used to test that the client decodes messages correctly if data is delivered to it
  /// byte-by-byte instead of in larger chunks that contain entire messages.
  @_spi(Testing)
  public func send(_rawData dispatchData: DispatchData) {
    queue.sync {
      self.send(data: dispatchData)
    }
  }

  /// Send the given message to the receiving end of the connection.
  ///
  /// If an unrecoverable error occurred on the channel's file descriptor, the connection gets closed.
  ///
  /// - Important: Must be called on `queue`
  func send(_ message: JSONRPCMessage) {
    dispatchPrecondition(condition: .onQueue(queue))

    let encoder = JSONEncoder()

    let data: Data
    do {
      data = try encoder.encode(message)
    } catch {
      // FIXME: attempt recovery?
      fatalError("unexpected error while encoding response: \(error)")
    }

    var dispatchData = DispatchData.empty
    let header = "Content-Length: \(data.count)\r\n\r\n"
    header.utf8.map { $0 }.withUnsafeBytes { buffer in
      dispatchData.append(buffer)
    }
    data.withUnsafeBytes { rawBufferPointer in
      dispatchData.append(rawBufferPointer)
    }

    send(data: dispatchData)
  }

  /// Close the connection.
  ///
  /// The user-provided close handler will be called *asynchronously* when all outstanding I/O
  /// operations have completed. No new I/O will be accepted after `close` returns.
  public func close() {
    queue.sync { closeAssumingOnQueue() }
  }

  /// Close the connection, assuming that the code is already executing on `queue`.
  ///
  /// - Important: Must be called on `queue`.
  private func closeAssumingOnQueue() {
    dispatchPrecondition(condition: .onQueue(queue))
    sendQueue.sync {
      guard state == .running else { return }
      state = .closed

      logger.log("closing JSONRPCConnection...")
      // Attempt to close the reader immediately; we do not need to accept remaining inputs.
      receiveIO.close(flags: .stop)
      // Close the writer after it finishes outstanding work.
      sendIO.close()
    }
  }

  /// Request id for the next outgoing request.
  ///
  /// - Important: Must be called on `queue`
  private func nextRequestID() -> RequestID {
    dispatchPrecondition(condition: .onQueue(queue))
    nextRequestIDStorage += 1
    return .number(nextRequestIDStorage)
  }

  // MARK: Connection interface

  /// Send the notification to the remote side of the notification.
  public func send(_ notification: some NotificationType) {
    queue.async {
      logger.info(
        """
        Sending notification to \(self.name, privacy: .public)
        \(notification.forLogging)
        """
      )
      self.send(.notification(notification))
    }
  }

  /// Send the given request to the remote side of the connection.
  ///
  /// When the receiving end replies to the request, execute `reply` with the response.
  public func send<Request: RequestType>(
    _ request: Request,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) -> RequestID {
    let id: RequestID = self.queue.sync {
      let id = nextRequestID()

      guard readyToSend() else {
        reply(.failure(.serverCancelled))
        return id
      }

      outstandingRequests[id] = OutstandingRequest(
        responseType: Request.Response.self,
        replyHandler: { anyResult in
          let result = anyResult.map { $0 as! Request.Response }
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
      )
      logger.info(
        """
        Sending request to \(self.name, privacy: .public) (id: \(id, privacy: .public)):
        \(request.forLogging)
        """
      )

      send(.request(request, id: id))
      return id
    }

    return id
  }

  /// After the remote side of the connection sent a request to us, return a reply to the remote side.
  public func sendReply(_ response: LSPResult<ResponseType>, id: RequestID) {
    queue.async {
      switch response {
      case .success(let result):
        self.send(.response(result, id: id))
      case .failure(let error):
        self.send(.errorResponse(error, id: id))
      }
    }
  }
}
