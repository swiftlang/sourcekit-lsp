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

import Foundation
import LSPTestSupport
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKCore
import SKSupport
import SourceKitLSP
import XCTest

extension SourceKitServer.Options {
  /// The default SourceKitServer options for testing.
  public static var testDefault = Self(swiftPublishDiagnosticsDebounceDuration: 0)
}

/// A mock SourceKit-LSP client (aka. a mock editor) that behaves like an editor
/// for testing purposes.
///
/// It can send requests to the LSP server and receive requests or notifications
/// that the server sends to the client.
public final class TestSourceKitLSPClient: MessageHandler {
  /// A function that takes a request and returns the request's response.
  public typealias RequestHandler<Request: RequestType> = (Request) -> Request.Response

  /// The ID that should be assigned to the next request sent to the `server`.
  private var nextRequestID: Int = 0

  /// If the server is not using the global module cache, the path of the local
  /// module cache.
  ///
  /// This module cache will be deleted when the test server is destroyed.
  private let moduleCache: URL?

  /// The server that handles the requests.
  public let server: SourceKitServer

  /// The connection via which the server sends requests and notifications to us.
  private let serverToClientConnection: LocalConnection

  /// Stream of the notifications that the server has sent to the client.
  private let notifications: AsyncStream<any NotificationType>

  /// Continuation to add a new notification from the ``server`` to the `notifications` stream.
  private let notificationYielder: AsyncStream<any NotificationType>.Continuation

  /// The request handlers that have been set by `handleNextRequest`.
  ///
  /// Conceptually, this is an array of `RequestHandler<any RequestType>` but
  /// since we can't express this in the Swift type system, we use `[Any]`.
  private var requestHandlers: [Any] = []

  /// - Parameters:
  ///   - useGlobalModuleCache: If `false`, the server will use its own module
  ///     cache in an empty temporary directory instead of the global module cache.
  public init(serverOptions: SourceKitServer.Options = .testDefault, useGlobalModuleCache: Bool = true) {
    if !useGlobalModuleCache {
      moduleCache = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    } else {
      moduleCache = nil
    }
    var serverOptions = serverOptions
    if let moduleCache {
      serverOptions.buildSetup.flags.swiftCompilerFlags += ["-module-cache-path", moduleCache.path]
    }

    var notificationYielder: AsyncStream<any NotificationType>.Continuation!
    self.notifications = AsyncStream { continuation in
      notificationYielder = continuation
    }
    self.notificationYielder = notificationYielder

    let clientConnection = LocalConnection()
    self.serverToClientConnection = clientConnection
    server = SourceKitServer(
      client: clientConnection,
      options: serverOptions,
      onExit: {
        clientConnection.close()
      }
    )

    self.serverToClientConnection.start(handler: WeakMessageHandler(self))
  }

  deinit {
    // It's really unfortunate that there are no async deinits. If we had async
    // deinits, we could await the sending of a ShutdownRequest.
    let sema = DispatchSemaphore(value: 0)
    nextRequestID += 1
    server.handle(ShutdownRequest(), id: .number(nextRequestID), from: ObjectIdentifier(self)) { result in
      sema.signal()
    }
    sema.wait()
    self.send(ExitNotification())

    if let moduleCache {
      try? FileManager.default.removeItem(at: moduleCache)
    }
  }

  // MARK: - Sending messages

  /// Send the request to `server` and return the request result.
  public func send<R: RequestType>(_ request: R) async throws -> R.Response {
    nextRequestID += 1
    return try await withCheckedThrowingContinuation { continuation in
      server.handle(request, id: .number(self.nextRequestID), from: ObjectIdentifier(self)) { result in
        continuation.resume(with: result)
      }
    }
  }

  /// Send the notification to `server`.
  public func send(_ notification: some NotificationType) {
    server.handle(notification, from: ObjectIdentifier(self))
  }

  // MARK: - Handling messages sent to the editor

  /// Await the next notification that is sent to the client.
  ///
  /// - Note: This also returns any notifications sent before the call to
  ///   `nextNotification`.
  public func nextNotification(timeout: TimeInterval = defaultTimeout) async throws -> any NotificationType {
    struct TimeoutError: Error, CustomStringConvertible {
      var description: String = "Failed to receive next notification within timeout"
    }

    return try await withThrowingTaskGroup(of: (any NotificationType).self) { taskGroup in
      taskGroup.addTask {
        for await notification in self.notifications {
          return notification
        }
        throw TimeoutError()
      }
      taskGroup.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw TimeoutError()
      }
      let result = try await taskGroup.next()!
      taskGroup.cancelAll()
      return result
    }
  }

  /// Await the next diagnostic notification sent to the client.
  ///
  /// If the next notification is not a `PublishDiagnosticsNotification`, this
  /// methods throws.
  public func nextDiagnosticsNotification(
    timeout: TimeInterval = defaultTimeout
  ) async throws -> PublishDiagnosticsNotification {
    struct CastError: Error, CustomStringConvertible {
      let actualType: any NotificationType.Type

      var description: String { "Expected a publish diagnostics notification but got '\(actualType)'" }
    }

    let nextNotification = try await nextNotification(timeout: timeout)
    guard let diagnostics = nextNotification as? PublishDiagnosticsNotification else {
      throw CastError(actualType: type(of: nextNotification))
    }
    return diagnostics
  }

  /// Handle the next request that is sent to the client with the given handler.
  ///
  /// By default, `TestSourceKitServer` emits an `XCTFail` if a request is sent
  /// to the client, since it doesn't know how to handle it. This allows the
  /// simulation of a single request's handling on the client.
  ///
  /// If the next request that is sent to the client is of a different kind than
  /// the given handler, `TestSourceKitServer` will emit an `XCTFail`.
  public func handleNextRequest<R: RequestType>(_ requestHandler: @escaping RequestHandler<R>) {
    requestHandlers.append(requestHandler)
  }

  // MARK: - Conformance to MessageHandler

  /// - Important: Implementation detail of `TestSourceKitServer`. Do not call
  ///   from tests.
  public func handle(_ params: some NotificationType, from clientID: ObjectIdentifier) {
    notificationYielder.yield(params)
  }

  /// - Important: Implementation detail of `TestSourceKitServer`. Do not call
  ///   from tests.
  public func handle<Request: RequestType>(
    _ params: Request,
    id: LanguageServerProtocol.RequestID,
    from clientID: ObjectIdentifier,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) {
    guard let requestHandler = requestHandlers.first else {
      XCTFail("Received unexpected request \(Request.method)")
      reply(.failure(.methodNotFound(Request.method)))
      return
    }
    guard let requestHandler = requestHandler as? RequestHandler<Request> else {
      print("\(RequestHandler<Request>.self)")
      XCTFail("Received request of unexpected type \(Request.method)")
      reply(.failure(.methodNotFound(Request.method)))
      return
    }
    reply(.success(requestHandler(params)))
    requestHandlers.removeFirst()
  }
}

// MARK: - WeakMessageHelper

/// Wrapper around a weak `MessageHandler`.
///
/// This allows us to set the ``TestSourceKitServer`` as the message handler of
/// `SourceKitServer` without retaining it.
private class WeakMessageHandler: MessageHandler {
  private weak var handler: (any MessageHandler)?

  init(_ handler: any MessageHandler) {
    self.handler = handler
  }

  func handle(_ params: some LanguageServerProtocol.NotificationType, from clientID: ObjectIdentifier) {
    handler?.handle(params, from: clientID)
  }

  func handle<Request: RequestType>(
    _ params: Request,
    id: LanguageServerProtocol.RequestID,
    from clientID: ObjectIdentifier,
    reply: @escaping (LanguageServerProtocol.LSPResult<Request.Response>) -> Void
  ) {
    guard let handler = handler else {
      reply(.failure(.unknown("Handler has been deallocated")))
      return
    }
    handler.handle(params, id: id, from: clientID, reply: reply)
  }
}
