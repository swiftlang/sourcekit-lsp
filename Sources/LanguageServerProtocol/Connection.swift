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

// MARK: - WeakMessageHelper

/// Wrapper around a weak `MessageHandler`.
///
/// This allows us to eg. set the ``TestSourceKitLSPClient`` as the message handler of
/// `SourceKitLSPServer` without retaining it.
public final class WeakMessageHandler: MessageHandler, Sendable {
  // `nonisolated(unsafe)` is fine because `handler` is never modified, only if the weak reference is deallocated, which
  // is atomic.
  private nonisolated(unsafe) weak var handler: (any MessageHandler)?

  public init(_ handler: any MessageHandler) {
    self.handler = handler
  }

  public func handle(_ params: some LanguageServerProtocol.NotificationType) {
    handler?.handle(params)
  }

  public func handle<Request: RequestType>(
    _ params: Request,
    id: LanguageServerProtocol.RequestID,
    reply: @Sendable @escaping (LanguageServerProtocol.LSPResult<Request.Response>) -> Void
  ) {
    guard let handler = handler else {
      reply(.failure(.unknown("Handler has been deallocated")))
      return
    }
    handler.handle(params, id: id, reply: reply)
  }
}
