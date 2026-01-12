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
import InProcessClient
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
import SKUtilities
import SourceKitD
package import SourceKitLSP
import SwiftExtensions
package import SwiftSyntax
package import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

extension SourceKitLSPOptions {
  package static func testDefault(
    backgroundIndexing: Bool = true,
    experimentalFeatures: Set<ExperimentalFeature> = [.synchronizeCopyFileMap]
  ) async throws -> SourceKitLSPOptions {
    let pluginPaths = try await sourceKitPluginPaths
    return SourceKitLSPOptions(
      sourcekitd: SourceKitDOptions(
        clientPlugin: try pluginPaths.clientPlugin.filePath,
        servicePlugin: try pluginPaths.servicePlugin.filePath
      ),
      backgroundIndexing: backgroundIndexing,
      experimentalFeatures: experimentalFeatures,
      swiftPublishDiagnosticsDebounceDuration: 0,
      workDoneProgressDebounceDuration: 0
    )
  }
}

private struct NotificationTimeoutError: Error, CustomStringConvertible {
  var description: String = "Failed to receive next notification within timeout"
}

/// A list of notifications that has been received by the SourceKit-LSP server but not handled from the test case yet.
///
/// We can't use an `AsyncStream` for this because an `AsyncStream` is cancelled if a task that calls
/// `AsyncStream.Iterator.next` is cancelled and we want to be able to wait for new notifications even if waiting for a
/// a previous notification timed out.
final class PendingNotifications: Sendable {
  private let values = ThreadSafeBox<[any NotificationType]>(initialValue: [])

  nonisolated func add(_ value: any NotificationType) {
    values.value.insert(value, at: 0)
  }

  func next(timeout: Duration, pollingInterval: Duration = .milliseconds(10)) async throws -> any NotificationType {
    for _ in 0..<Int(timeout.seconds / pollingInterval.seconds) {
      if let value = values.value.popLast() {
        return value
      }
      try await Task.sleep(for: pollingInterval)
    }
    throw NotificationTimeoutError()
  }
}

/// A mock SourceKit-LSP client (aka. a mock editor) that behaves like an editor
/// for testing purposes.
///
/// It can send requests to the LSP server and receive requests or notifications
/// that the server sends to the client.
package final class TestSourceKitLSPClient: MessageHandler, Sendable {
  /// A function that takes a request and returns the request's response.
  package typealias RequestHandler<Request: RequestType> = @Sendable (Request) -> Request.Response

  /// The ID that should be assigned to the next request sent to the `server`.
  private let nextRequestID = AtomicUInt32(initialValue: 0)

  /// The server that handles the requests.
  package let server: SourceKitLSPServer

  /// Whether pull or push-model diagnostics should be used.
  ///
  /// This is used to fail the `nextDiagnosticsNotification` function early in case the pull-diagnostics model is used
  /// to avoid a fruitful debug for why no diagnostic request is being sent push diagnostics have been explicitly
  /// disabled.
  private let usePullDiagnostics: Bool

  /// The connection via which the server sends requests and notifications to us.
  private let serverToClientConnection: LocalConnection

  /// The response of the initialize request.
  ///
  /// Must only be set from the initializer and not be accessed before the initializer has finished.
  package private(set) nonisolated(unsafe) var initializeResult: InitializeResult?

  /// Stream of the notifications that the server has sent to the client.
  private let notifications: PendingNotifications

  /// The request handlers that have been set by `handleNextRequest`.
  ///
  /// Conceptually, this is an array of `RequestHandler<any RequestType>` but
  /// since we can't express this in the Swift type system, we use `[Any]`.
  ///
  /// `isOneShort` if the request handler should only serve a single request and should be removed from
  /// `requestHandlers` after it has been called.
  private let requestHandlers: ThreadSafeBox<[(requestHandler: any Sendable, isOneShot: Bool)]> =
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
  ///   - usePullDiagnostics: Whether to use push diagnostics or use push-based diagnostics.
  ///   - enableBackgroundIndexing: Whether background indexing should be enabled in the project.
  ///   - workspaceFolders: Workspace folders to open.
  ///   - preInitialization: A closure that is called after the test client is created but before SourceKit-LSP is
  ///     initialized. This can be used to eg. register request handlers.
  ///   - cleanUp: A closure that is called when the `TestSourceKitLSPClient` is destructed.
  ///     This allows e.g. a `IndexedSingleSwiftFileTestProject` to delete its temporary files when they are no longer
  ///     needed.
  package init(
    options: SourceKitLSPOptions? = nil,
    hooks: Hooks = Hooks(),
    initialize: Bool = true,
    initializationOptions: LSPAny? = nil,
    capabilities: ClientCapabilities = ClientCapabilities(),
    toolchainRegistry: ToolchainRegistry = .forTesting,
    usePullDiagnostics: Bool = true,
    enableBackgroundIndexing: Bool = false,
    workspaceFolders: [WorkspaceFolder]? = nil,
    preInitialization: ((TestSourceKitLSPClient) -> Void)? = nil,
    cleanUp: @Sendable @escaping () -> Void = {}
  ) async throws {
    var options =
      if let options {
        options
      } else {
        try await SourceKitLSPOptions.testDefault()
      }
    if let globalModuleCache = try globalModuleCache {
      options.swiftPMOrDefault.swiftCompilerFlags =
        (options.swiftPMOrDefault.swiftCompilerFlags ?? []) + ["-module-cache-path", try globalModuleCache.filePath]
    }
    options.backgroundIndexing = enableBackgroundIndexing
    if options.sourcekitdRequestTimeout == nil {
      options.sourcekitdRequestTimeout = defaultTimeout
    }

    self.notifications = PendingNotifications()

    let serverToClientConnection = LocalConnection(receiverName: "client")
    self.serverToClientConnection = serverToClientConnection
    server = SourceKitLSPServer(
      client: serverToClientConnection,
      toolchainRegistry: toolchainRegistry,
      languageServerRegistry: .staticallyKnownServices,
      options: options,
      hooks: hooks,
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
    }
    preInitialization?(self)
    if initialize {
      let capabilities = capabilities
      self.initializeResult = try await withTimeout(defaultTimeoutDuration) {
        try await self.send(
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
  }

  deinit {
    // It's really unfortunate that there are no async deinits. If we had async
    // deinits, we could await the sending of a ShutdownRequest.
    let shutdownSemaphore = WrappedSemaphore(name: "Shutdown")
    server.handle(ShutdownRequest(), id: .number(Int(nextRequestID.fetchAndIncrement()))) { result in
      shutdownSemaphore.signal()
    }
    shutdownSemaphore.waitOrXCTFail()
    self.send(ExitNotification())

    cleanUp()

    let flushSemaphore = WrappedSemaphore(name: "Flush log")
    Task {
      await NonDarwinLogger.flush()
      flushSemaphore.signal()
    }
    flushSemaphore.waitOrXCTFail()
  }

  // MARK: - Sending messages

  /// Send the request to `server` and return the request result.
  package func send<R: RequestType>(_ request: R) async throws(ResponseError) -> R.Response {
    let response = await withCheckedContinuation { continuation in
      self.send(request) { result in
        continuation.resume(returning: result)
      }
    }
    return try response.get()
  }

  /// Variant of `send` above that allows the response to be discarded if it is a `VoidResponse`.
  package func send<R: RequestType>(_ request: R) async throws(ResponseError) where R.Response == VoidResponse {
    let _: VoidResponse = try await self.send(request)
  }

  /// Send the request to `server` and return the result via a completion handler.
  ///
  /// This version of the `send` function should only be used if some action needs to be performed after the request is
  /// sent but before it returns a result.
  @discardableResult
  package func send<R: RequestType>(
    _ request: R,
    completionHandler: @Sendable @escaping (LSPResult<R.Response>) -> Void
  ) -> RequestID {
    let requestID = RequestID.number(Int(nextRequestID.fetchAndIncrement()))
    let replyOutstanding = ThreadSafeBox<Bool?>(initialValue: true)
    let timeoutTask = Task {
      try await Task.sleep(for: defaultTimeoutDuration)
      if replyOutstanding.takeValue() ?? false {
        completionHandler(
          .failure(ResponseError.unknown("\(R.method) request timed out after \(defaultTimeoutDuration)"))
        )
      }
      server.handle(CancelRequestNotification(id: requestID))
    }
    server.handle(request, id: requestID) { result in
      if replyOutstanding.takeValue() ?? false {
        completionHandler(result)
      }
      timeoutTask.cancel()
    }
    return requestID
  }

  /// Send the notification to `server`.
  package func send(_ notification: some NotificationType) {
    server.handle(notification)
  }

  // MARK: - Handling messages sent to the editor

  /// Await the next notification that is sent to the client.
  ///
  /// - Note: This also returns any notifications sent before the call to
  ///   `nextNotification`.
  package func nextNotification(timeout: Duration = defaultTimeoutDuration) async throws -> any NotificationType {
    return try await notifications.next(timeout: timeout)
  }

  /// Await the next diagnostic notification sent to the client.
  ///
  /// If the next notification is not a `PublishDiagnosticsNotification`, this
  /// methods throws.
  package func nextDiagnosticsNotification(
    timeout: Duration = defaultTimeoutDuration
  ) async throws -> PublishDiagnosticsNotification {
    guard !usePullDiagnostics else {
      struct PushDiagnosticsError: Error, CustomStringConvertible {
        var description = "Client is using the diagnostics and will thus never receive a diagnostics notification"
      }
      throw PushDiagnosticsError()
    }
    return try await nextNotification(ofType: PublishDiagnosticsNotification.self, timeout: timeout)
  }

  /// Waits for the next notification of the given type to be sent to the client that satisfies the given predicate.
  /// Ignores any notifications that are of a different type or that don't satisfy the predicate.
  package func nextNotification<ExpectedNotificationType: NotificationType>(
    ofType: ExpectedNotificationType.Type,
    satisfying predicate: (ExpectedNotificationType) throws -> Bool = { _ in true },
    timeout: Duration = defaultTimeoutDuration
  ) async throws -> ExpectedNotificationType {
    while true {
      let nextNotification = try await nextNotification(timeout: timeout)
      if let notification = nextNotification as? ExpectedNotificationType, try predicate(notification) {
        return notification
      }
    }
  }

  /// Asserts that the test client does not receive a notification of the given type and satisfying the given predicate
  /// within the given duration.
  ///
  /// For stable tests, the code that triggered the notification should be run before this assertion instead of relying
  /// on the duration.
  ///
  /// The duration should not be 0 because we need to allow `nextNotification` some time to get the notification out of
  /// the `notifications` `AsyncStream`.
  package func assertDoesNotReceiveNotification<ExpectedNotificationType: NotificationType>(
    ofType: ExpectedNotificationType.Type,
    satisfying predicate: (ExpectedNotificationType) -> Bool = { _ in true },
    within duration: Duration = .seconds(0.2)
  ) async throws {
    do {
      let notification = try await nextNotification(
        ofType: ExpectedNotificationType.self,
        satisfying: predicate,
        timeout: duration
      )
      XCTFail("Did not expect to receive notification but received \(notification)")
    } catch is NotificationTimeoutError {}
  }

  /// Handle the next request of the given type that is sent to the client.
  ///
  /// The request handler will only handle a single request. If the request is called again, the request handler won't
  /// call again
  package func handleSingleRequest<R: RequestType>(_ requestHandler: @escaping RequestHandler<R>) {
    requestHandlers.value.append((requestHandler: requestHandler, isOneShot: true))
  }

  /// Handle all requests of the given type that are sent to the client.
  package func handleMultipleRequests<R: RequestType>(_ requestHandler: @escaping RequestHandler<R>) {
    requestHandlers.value.append((requestHandler: requestHandler, isOneShot: false))
  }

  // MARK: - Conformance to MessageHandler

  /// - Important: Implementation detail of `TestSourceKitLSPServer`. Do not call from tests.
  package func handle(_ notification: some NotificationType) {
    notifications.add(notification)
  }

  /// - Important: Implementation detail of `TestSourceKitLSPClient`. Do not call from tests.
  package func handle<Request: RequestType>(
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
  package func openDocument(
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
package struct DocumentPositions {
  private let positions: [String: Position]

  package init(markers: [String: AbsolutePosition], textWithoutMarkers: String) {
    if markers.isEmpty {
      // No need to build a line table if we don't have any markers.
      positions = [:]
      return
    }

    let lineTable = LineTable(textWithoutMarkers)
    positions = markers.mapValues { offset in
      let (line, column) = lineTable.lineAndUTF16ColumnOf(utf8Offset: offset.utf8Offset)
      return Position(line: line, utf16index: column)
    }
  }

  package init(markedText: String) {
    let (markers, textWithoutMarker) = extractMarkers(markedText)
    self.init(markers: markers, textWithoutMarkers: textWithoutMarker)
  }

  fileprivate init(positions: [String: Position]) {
    self.positions = positions
  }

  package static func extract(from markedText: String) -> (positions: DocumentPositions, textWithoutMarkers: String) {
    let (markers, textWithoutMarkers) = extractMarkers(markedText)
    return (DocumentPositions(markers: markers, textWithoutMarkers: textWithoutMarkers), textWithoutMarkers)
  }

  /// Returns the position of the given marker and traps if the document from which these `DocumentPositions` were
  /// derived didn't contain the marker.
  package subscript(_ marker: String) -> Position {
    guard let position = positions[marker] else {
      preconditionFailure("Could not find marker '\(marker)' in source code")
    }
    return position
  }

  /// Returns all position makers within these `DocumentPositions`.
  package var allMarkers: [String] {
    return positions.keys.sorted()
  }
}
