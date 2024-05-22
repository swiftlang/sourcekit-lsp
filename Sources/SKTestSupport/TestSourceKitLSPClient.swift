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

import CAtomics
import Foundation
import InProcessClient
import LSPTestSupport
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
@_spi(Testing) import SKCore
import SKSupport
import SourceKitLSP
import SwiftSyntax
import XCTest

extension SourceKitLSPServer.Options {
  /// The default SourceKitLSPServer options for testing.
  public static let testDefault = Self(swiftPublishDiagnosticsDebounceDuration: 0)
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
  /// `nonisolated(unsafe)` is fine because `nextRequestID` is atomic.
  private nonisolated(unsafe) var nextRequestID = AtomicUInt32(initialValue: 0)

  /// If the server is not using the global module cache, the path of the local
  /// module cache.
  ///
  /// This module cache will be deleted when the test server is destroyed.
  private let moduleCache: URL?

  /// The server that handles the requests.
  public let server: SourceKitLSPServer

  /// Whether pull or push-model diagnostics should be used.
  ///
  /// This is used to fail the `nextDiagnosticsNotification` function early in case the pull-diagnostics model is used
  /// to avoid a fruitful debug for why no diagnostic request is being sent push diagnostics have been explicitly
  /// disabled.
  private let usePullDiagnostics: Bool

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
  ///
  /// `isOneShort` if the request handler should only serve a single request and should be removed from
  /// `requestHandlers` after it has been called.
  private nonisolated(unsafe) var requestHandlers: ThreadSafeBox<[(requestHandler: Any, isOneShot: Bool)]> =
    ThreadSafeBox(initialValue: [])

  /// A closure that is called when the `TestSourceKitLSPClient` is destructed.
  ///
  /// This allows e.g. a `IndexedSingleSwiftFileTestProject` to delete its temporary files when they are no longer needed.
  private let cleanUp: @Sendable () -> Void

  /// - Parameters:
  ///   - serverOptions: The equivalent of the command line options with which sourcekit-lsp should be started
  ///   - useGlobalModuleCache: If `false`, the server will use its own module
  ///     cache in an empty temporary directory instead of the global module cache.
  ///   - initialize: Whether an `InitializeRequest` should be automatically sent to the SourceKit-LSP server.
  ///     `true` by default
  ///   - initializationOptions: Initialization options to pass to the SourceKit-LSP server.
  ///   - capabilities: The test client's capabilities.
  ///   - usePullDiagnostics: Whether to use push diagnostics or use push-based diagnostics
  ///   - workspaceFolders: Workspace folders to open.
  ///   - preInitialization: A closure that is called after the test client is created but before SourceKit-LSP is
  ///     initialized. This can be used to eg. register request handlers.
  ///   - cleanUp: A closure that is called when the `TestSourceKitLSPClient` is destructed.
  ///     This allows e.g. a `IndexedSingleSwiftFileTestProject` to delete its temporary files when they are no longer
  ///     needed.
  public init(
    serverOptions: SourceKitLSPServer.Options = .testDefault,
    useGlobalModuleCache: Bool = true,
    initialize: Bool = true,
    initializationOptions: LSPAny? = nil,
    capabilities: ClientCapabilities = ClientCapabilities(),
    usePullDiagnostics: Bool = true,
    workspaceFolders: [WorkspaceFolder]? = nil,
    preInitialization: ((TestSourceKitLSPClient) -> Void)? = nil,
    cleanUp: @Sendable @escaping () -> Void = {}
  ) async throws {
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

    let serverToClientConnection = LocalConnection(name: "client")
    self.serverToClientConnection = serverToClientConnection
    server = SourceKitLSPServer(
      client: serverToClientConnection,
      toolchainRegistry: ToolchainRegistry.forTesting,
      options: serverOptions,
      onExit: {
        serverToClientConnection.close()
      }
    )

    self.cleanUp = cleanUp
    self.usePullDiagnostics = usePullDiagnostics
    self.serverToClientConnection.start(handler: WeakMessageHandler(self))

    var capabilities = capabilities
    if usePullDiagnostics {
      if capabilities.textDocument == nil {
        capabilities.textDocument = TextDocumentClientCapabilities()
      }
      guard capabilities.textDocument!.diagnostic == nil else {
        struct ConflictingDiagnosticsError: Error, CustomStringConvertible {
          var description: String {
            "usePullDiagnostics = false is not supported if capabilities already contain diagnostic options"
          }
        }
        throw ConflictingDiagnosticsError()
      }
      capabilities.textDocument!.diagnostic = .init(dynamicRegistration: true)
      self.handleSingleRequest { (request: RegisterCapabilityRequest) in
        XCTAssertEqual(request.registrations.only?.method, DocumentDiagnosticsRequest.method)
        return VoidResponse()
      }
      preInitialization?(self)
    }
    if initialize {
      _ = try await self.send(
        InitializeRequest(
          processId: nil,
          rootPath: nil,
          rootURI: nil,
          initializationOptions: initializationOptions,
          capabilities: capabilities,
          trace: .off,
          workspaceFolders: workspaceFolders
        )
      )
    }
  }

  deinit {
    // It's really unfortunate that there are no async deinits. If we had async
    // deinits, we could await the sending of a ShutdownRequest.
    let sema = DispatchSemaphore(value: 0)
    server.handle(ShutdownRequest(), id: .number(Int(nextRequestID.fetchAndIncrement()))) { result in
      sema.signal()
    }
    sema.wait()
    self.send(ExitNotification())

    if let moduleCache {
      try? FileManager.default.removeItem(at: moduleCache)
    }
    cleanUp()
  }

  // MARK: - Sending messages

  /// Send the request to `server` and return the request result.
  public func send<R: RequestType>(_ request: R) async throws -> R.Response {
    return try await withCheckedThrowingContinuation { continuation in
      server.handle(request, id: .number(Int(nextRequestID.fetchAndIncrement()))) { result in
        continuation.resume(with: result)
      }
    }
  }

  /// Send the notification to `server`.
  public func send(_ notification: some NotificationType) {
    server.handle(notification)
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
    guard !usePullDiagnostics else {
      struct PushDiagnosticsError: Error, CustomStringConvertible {
        var description = "Client is using the diagnostics and will thus never receive a diagnostics notification"
      }
      throw PushDiagnosticsError()
    }
    return try await nextNotification(ofType: PublishDiagnosticsNotification.self, timeout: timeout)
  }

  /// Waits for the next notification of the given type to be sent to the client. Ignores any notifications that are of
  /// a different type.
  public func nextNotification<ExpectedNotificationType: NotificationType>(
    ofType: ExpectedNotificationType.Type,
    timeout: TimeInterval = defaultTimeout
  ) async throws -> ExpectedNotificationType {
    while true {
      let nextNotification = try await nextNotification(timeout: timeout)
      if let notification = nextNotification as? ExpectedNotificationType {
        return notification
      }
    }
  }

  /// Handle the next request of the given type that is sent to the client.
  ///
  /// The request handler will only handle a single request. If the request is called again, the request handler won't
  /// call again
  public func handleSingleRequest<R: RequestType>(_ requestHandler: @escaping RequestHandler<R>) {
    requestHandlers.value.append((requestHandler: requestHandler, isOneShot: true))
  }

  /// Handle all requests of the given type that are sent to the client.
  public func handleMultipleRequests<R: RequestType>(_ requestHandler: @escaping RequestHandler<R>) {
    requestHandlers.value.append((requestHandler: requestHandler, isOneShot: false))
  }

  // MARK: - Conformance to MessageHandler

  /// - Important: Implementation detail of `TestSourceKitLSPServer`. Do not call from tests.
  public func handle(_ params: some NotificationType) {
    notificationYielder.yield(params)
  }

  /// - Important: Implementation detail of `TestSourceKitLSPClient`. Do not call from tests.
  public func handle<Request: RequestType>(
    _ params: Request,
    id: LanguageServerProtocol.RequestID,
    reply: @escaping (LSPResult<Request.Response>) -> Void
  ) {
    requestHandlers.withLock { requestHandlers in
      let requestHandlerIndexAndIsOneShot = requestHandlers.enumerated().compactMap {
        (index, handlerAndIsOneShot) -> (RequestHandler<Request>, Int, Bool)? in
        guard let handler = handlerAndIsOneShot.requestHandler as? RequestHandler<Request> else {
          return nil
        }
        return (handler, index, handlerAndIsOneShot.isOneShot)
      }.first
      guard let (requestHandler, index, isOneShot) = requestHandlerIndexAndIsOneShot else {
        reply(.failure(.methodNotFound(Request.method)))
        return
      }
      reply(.success(requestHandler(params)))
      if isOneShot {
        requestHandlers.remove(at: index)
      }
    }
  }

  // MARK: - Convenience functions

  /// Opens the document with the given text as the given URI.
  ///
  /// The version defaults to 0 and the language is inferred from the file's extension by default.
  ///
  /// If the text contained location markers like `1️⃣`, then these are stripped from the opened document and
  /// `DocumentPositions` are returned that map these markers to their position in the source file.
  @discardableResult
  public func openDocument(
    _ markedText: String,
    uri: DocumentURI,
    version: Int = 0,
    language: Language? = nil
  ) -> DocumentPositions {
    let (markers, textWithoutMarkers) = extractMarkers(markedText)
    var language = language
    if language == nil {
      guard let fileExtension = uri.fileURL?.pathExtension,
        let inferredLanguage = Language(fileExtension: fileExtension)
      else {
        preconditionFailure("Unable to infer language for file \(uri)")
      }
      language = inferredLanguage
    }

    self.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: language!,
          version: version,
          text: textWithoutMarkers
        )
      )
    )

    return DocumentPositions(markers: markers, textWithoutMarkers: textWithoutMarkers)
  }
}

// MARK: - DocumentPositions

/// Maps location marker like `1️⃣` to their position within a source file.
public struct DocumentPositions {
  private let positions: [String: Position]

  fileprivate init(markers: [String: Int], textWithoutMarkers: String) {
    if markers.isEmpty {
      // No need to build a line table if we don't have any markers.
      positions = [:]
      return
    }

    let lineTable = LineTable(textWithoutMarkers)
    positions = markers.mapValues { offset in
      let (line, column) = lineTable.lineAndUTF16ColumnOf(utf8Offset: offset)
      return Position(line: line, utf16index: column)
    }
  }

  public init(markedText: String) {
    let (markers, textWithoutMarker) = extractMarkers(markedText)
    self.init(markers: markers, textWithoutMarkers: textWithoutMarker)
  }

  fileprivate init(positions: [String: Position]) {
    self.positions = positions
  }

  /// Returns the position of the given marker and traps if the document from which these `DocumentPositions` were
  /// derived didn't contain the marker.
  public subscript(_ marker: String) -> Position {
    guard let position = positions[marker] else {
      preconditionFailure("Could not find marker '\(marker)' in source code")
    }
    return position
  }

  /// Returns all position makers within these `DocumentPositions`.
  public var allMarkers: [String] {
    return positions.keys.sorted()
  }
}

// MARK: - WeakMessageHelper

/// Wrapper around a weak `MessageHandler`.
///
/// This allows us to set the ``TestSourceKitLSPClient`` as the message handler of
/// `SourceKitLSPServer` without retaining it.
private final class WeakMessageHandler: MessageHandler, Sendable {
  // `nonisolated(unsafe)` is fine because `handler` is never modified, only if the weak reference is deallocated, which
  // is atomic.
  private nonisolated(unsafe) weak var handler: (any MessageHandler)?

  init(_ handler: any MessageHandler) {
    self.handler = handler
  }

  func handle(_ params: some LanguageServerProtocol.NotificationType) {
    handler?.handle(params)
  }

  func handle<Request: RequestType>(
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
