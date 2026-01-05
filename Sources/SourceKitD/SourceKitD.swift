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

package import Csourcekitd
package import Foundation
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

extension sourcekitd_api_keys: @unchecked Sendable {}
extension sourcekitd_api_requests: @unchecked Sendable {}
extension sourcekitd_api_values: @unchecked Sendable {}

fileprivate extension ThreadSafeBox {
  /// If the wrapped value is `nil`, run `compute` and store the computed value. If it is not `nil`, return the stored
  /// value.
  func computeIfNil<WrappedValue: Sendable>(compute: () -> WrappedValue) -> WrappedValue where T == WrappedValue? {
    return withLock { (value: inout WrappedValue?) -> WrappedValue in
      if let value {
        return value
      }
      let computed = compute()
      value = computed
      return computed
    }
  }
}

#if canImport(Darwin)
private func setenv(name: String, value: String, override: Bool) throws {
  struct FailedToSetEnvError: Error {
    let errorCode: Int32
  }
  try name.withCString { name in
    try value.withCString { value in
      let result = setenv(name, value, override ? 0 : 1)
      if result != 0 {
        throw FailedToSetEnvError(errorCode: result)
      }
    }
  }
}
#endif

private struct SourceKitDRequestHandle: Sendable {
  /// `nonisolated(unsafe)` is fine because we just use the handle as an opaque value.
  nonisolated(unsafe) let handle: sourcekitd_api_request_handle_t
}

package struct PluginPaths: Equatable, CustomLogStringConvertible {
  package let clientPlugin: URL
  package let servicePlugin: URL

  package init(clientPlugin: URL, servicePlugin: URL) {
    self.clientPlugin = clientPlugin
    self.servicePlugin = servicePlugin
  }

  package var description: String {
    "(client: \(clientPlugin), service: \(servicePlugin))"
  }

  var redactedDescription: String {
    "(client: \(clientPlugin.description.hashForLogging), service: \(servicePlugin.description.hashForLogging))"
  }
}

package enum SKDError: Error, Equatable {
  /// The service has crashed.
  case connectionInterrupted

  /// The request was unknown or had an invalid or missing parameter.
  case requestInvalid(String)

  /// The request failed.
  case requestFailed(String)

  /// The request was cancelled.
  case requestCancelled

  /// The request exceeded the maximum allowed duration.
  case timedOut

  /// Loading a required symbol from the sourcekitd library failed.
  case missingRequiredSymbol(String)
}

/// Wrapper for sourcekitd, taking care of initialization, shutdown, and notification handler
/// multiplexing.
///
/// Users of this class should not call the api functions `initialize`, `shutdown`, or
/// `set_notification_handler`, which are global state managed internally by this class.
package actor SourceKitD {
  /// The path to the sourcekitd dylib.
  nonisolated package let path: URL

  /// The handle to the dylib.
  private let dylib: DLHandle

  /// The sourcekitd API functions.
  nonisolated package let api: sourcekitd_api_functions_t

  /// General API for the SourceKit service and client framework, eg. for plugin initialization and to set up custom
  /// variant functions.
  ///
  /// This must not be referenced outside of `SwiftSourceKitPlugin`, `SwiftSourceKitPluginCommon`, or
  /// `SwiftSourceKitClientPlugin`.
  package nonisolated var pluginApi: sourcekitd_plugin_api_functions_t { try! pluginApiResult.get() }
  private let pluginApiResult: Result<sourcekitd_plugin_api_functions_t, any Error>

  /// The API with which the SourceKit plugin handles requests.
  ///
  /// This must not be referenced outside of `SwiftSourceKitPlugin`.
  package nonisolated var servicePluginApi: sourcekitd_service_plugin_api_functions_t {
    try! servicePluginApiResult.get()
  }
  private let servicePluginApiResult: Result<sourcekitd_service_plugin_api_functions_t, any Error>

  /// The API with which the SourceKit plugin communicates with the type-checker in-process.
  ///
  /// This must not be referenced outside of `SwiftSourceKitPlugin`.
  package nonisolated var ideApi: sourcekitd_ide_api_functions_t { try! ideApiResult.get() }
  private let ideApiResult: Result<sourcekitd_ide_api_functions_t, any Error>

  /// Convenience for accessing known keys.
  ///
  /// These need to be computed dynamically so that a client has the chance to register a UID handler between the
  /// initialization of the SourceKit plugin and the first request being handled by it.
  private let _keys: ThreadSafeBox<sourcekitd_api_keys?> = ThreadSafeBox(initialValue: nil)
  package nonisolated var keys: sourcekitd_api_keys {
    _keys.computeIfNil { sourcekitd_api_keys(api: self.api) }
  }

  /// Convenience for accessing known request names.
  ///
  /// These need to be computed dynamically so that a client has the chance to register a UID handler between the
  /// initialization of the SourceKit plugin and the first request being handled by it.
  private let _requests: ThreadSafeBox<sourcekitd_api_requests?> = ThreadSafeBox(initialValue: nil)
  package nonisolated var requests: sourcekitd_api_requests {
    _requests.computeIfNil { sourcekitd_api_requests(api: self.api) }
  }

  /// Convenience for accessing known request/response values.
  ///
  /// These need to be computed dynamically so that a client has the chance to register a UID handler between the
  /// initialization of the SourceKit plugin and the first request being handled by it.
  private let _values: ThreadSafeBox<sourcekitd_api_values?> = ThreadSafeBox(initialValue: nil)
  package nonisolated var values: sourcekitd_api_values {
    _values.computeIfNil { sourcekitd_api_values(api: self.api) }
  }

  private nonisolated let notificationHandlingQueue = AsyncQueue<Serial>()

  /// List of notification handlers that will be called for each notification.
  private var notificationHandlers: [WeakSKDNotificationHandler] = []

  /// List of hooks that should be executed and that need to finish executing before a request is sent to sourcekitd.
  private var preRequestHandlingHooks: [UUID: @Sendable (SKDRequestDictionary) async -> Void] = [:]

  /// List of hooks that should be executed after a request sent to sourcekitd.
  private var requestHandlingHooks: [UUID: (SKDRequestDictionary) -> Void] = [:]

  package static func getOrCreate(
    dylibPath: URL,
    pluginPaths: PluginPaths?
  ) async throws -> SourceKitD {
    try await SourceKitDRegistry.shared.getOrAdd(dylibPath, pluginPaths: pluginPaths) {
      return try SourceKitD(dylib: dylibPath, pluginPaths: pluginPaths)
    }
  }

  package init(dylib path: URL, pluginPaths: PluginPaths?, initialize: Bool = true) throws {
    #if os(Windows)
    let dlopenModes: DLOpenFlags = []
    #else
    let dlopenModes: DLOpenFlags = [.lazy, .local, .first]
    #endif
    let dlhandle = try dlopen(path.filePath, mode: dlopenModes)
    try self.init(
      dlhandle: dlhandle,
      path: path,
      pluginPaths: pluginPaths,
      initialize: initialize
    )
  }

  /// Create a `SourceKitD` instance from an existing `DLHandle`. `SourceKitD` takes over ownership of the `DLHandler`
  /// and will close it when the `SourceKitD` instance gets deinitialized or if the initializer throws.
  package init(dlhandle: DLHandle, path: URL, pluginPaths: PluginPaths?, initialize: Bool) throws {
    do {
      self.path = path
      self.dylib = dlhandle
      let api = try sourcekitd_api_functions_t(dlhandle)
      self.api = api

      // We load the plugin-related functions eagerly so the members are initialized and we don't have data races on first
      // access to eg. `pluginApi`. But if one of the functions is missing, we will only emit that error when that family
      // of functions is being used. For example, it is expected that the plugin functions are not available in
      // SourceKit-LSP.
      self.ideApiResult = Result(catching: { try sourcekitd_ide_api_functions_t(dlhandle) })
      self.pluginApiResult = Result(catching: { try sourcekitd_plugin_api_functions_t(dlhandle) })
      self.servicePluginApiResult = Result(catching: { try sourcekitd_service_plugin_api_functions_t(dlhandle) })

      if let pluginPaths {
        api.register_plugin_path?(pluginPaths.clientPlugin.path, pluginPaths.servicePlugin.path)
      }
      if initialize {
        self.api.initialize()
      }

      if initialize {
        self.api.set_notification_handler { [weak self] rawResponse in
          guard let self, let rawResponse else { return }
          let response = SKDResponse(rawResponse, sourcekitd: self)
          self.notificationHandlingQueue.async {
            let handlers = await self.notificationHandlers.compactMap(\.value)

            for handler in handlers {
              handler.notification(response)
            }
          }
        }
      }
    } catch {
      orLog("Closing dlhandle after opening sourcekitd failed") {
        try? dlhandle.close()
      }
      throw error
    }
  }

  deinit {
    self.api.set_notification_handler(nil)
    self.api.shutdown()
    Task.detached(priority: .background) { [dylib, path] in
      orLog("Closing dylib \(path)") { try dylib.close() }
    }
  }

  /// Adds a new notification handler (referenced weakly).
  package func addNotificationHandler(_ handler: any SKDNotificationHandler) {
    notificationHandlers.removeAll(where: { $0.value == nil })
    notificationHandlers.append(.init(handler))
  }

  /// Removes a previously registered notification handler.
  package func removeNotificationHandler(_ handler: any SKDNotificationHandler) {
    notificationHandlers.removeAll(where: { $0.value == nil || $0.value === handler })
  }

  /// Execute `body` and invoke `hook` for every sourcekitd request that is sent during the execution time of `body`.
  ///
  /// Note that `hook` will not only be executed for requests sent *by* body but this may also include sourcekitd
  /// requests that were sent by other clients of the same `DynamicallyLoadedSourceKitD` instance that just happen to
  /// send a request during that time.
  ///
  /// This is intended for testing only.
  package func withPreRequestHandlingHook(
    body: () async throws -> Void,
    hook: @escaping @Sendable (SKDRequestDictionary) async -> Void
  ) async rethrows {
    let id = UUID()
    preRequestHandlingHooks[id] = hook
    defer { preRequestHandlingHooks[id] = nil }
    try await body()
  }

  func willSend(request: SKDRequestDictionary) async {
    let request = request
    for hook in preRequestHandlingHooks.values {
      await hook(request)
    }
  }

  /// Execute `body` and invoke `hook` for every sourcekitd request that is sent during the execution time of `body`.
  ///
  /// Note that `hook` will not only be executed for requests sent *by* body but this may also include sourcekitd
  /// requests that were sent by other clients of the same `DynamicallyLoadedSourceKitD` instance that just happen to
  /// send a request during that time.
  ///
  /// This is intended for testing only.
  package func withRequestHandlingHook(
    body: () async throws -> Void,
    hook: @escaping (SKDRequestDictionary) -> Void
  ) async rethrows {
    let id = UUID()
    requestHandlingHooks[id] = hook
    defer { requestHandlingHooks[id] = nil }
    try await body()
  }

  func didSend(request: SKDRequestDictionary) {
    for hook in requestHandlingHooks.values {
      hook(request)
    }
  }

  private struct ContextualRequest {
    enum Kind {
      case editorOpen
      case codeCompleteOpen
    }
    let kind: Kind
    let request: SKDRequestDictionary
  }

  private var contextualRequests: [URL: [ContextualRequest]] = [:]

  private func recordContextualRequest(
    requestUid: sourcekitd_api_uid_t,
    request: SKDRequestDictionary,
    documentUrl: URL?
  ) {
    guard let documentUrl else {
      return
    }
    switch requestUid {
    case requests.editorOpen:
      contextualRequests[documentUrl] = [ContextualRequest(kind: .editorOpen, request: request)]
    case requests.editorClose:
      contextualRequests[documentUrl] = nil
    case requests.codeCompleteOpen:
      contextualRequests[documentUrl, default: []].removeAll(where: { $0.kind == .codeCompleteOpen })
      contextualRequests[documentUrl, default: []].append(ContextualRequest(kind: .codeCompleteOpen, request: request))
    case requests.codeCompleteClose:
      contextualRequests[documentUrl, default: []].removeAll(where: { $0.kind == .codeCompleteOpen })
      if contextualRequests[documentUrl]?.isEmpty ?? false {
        // This should never happen because we should still have an active `.editorOpen` contextual request but just be
        // safe in case we don't.
        contextualRequests[documentUrl] = nil
      }
    default:
      break
    }
  }

  /// - Parameters:
  ///   - request: The request to send to sourcekitd.
  ///   - timeout: The maximum duration how long to wait for a response. If no response is returned within this time,
  ///     declare the request as having timed out.
  ///   - fileContents: The contents of the file that the request operates on. If sourcekitd crashes, the file contents
  ///     will be logged.
  package func send(
    _ requestUid: KeyPath<sourcekitd_api_requests, sourcekitd_api_uid_t>,
    _ request: SKDRequestDictionary,
    timeout: Duration,
    restartTimeout: Duration,
    documentUrl: URL?,
    fileContents: String?
  ) async throws -> SKDResponseDictionary {
    request.set(keys.request, to: requests[keyPath: requestUid])
    recordContextualRequest(requestUid: requests[keyPath: requestUid], request: request, documentUrl: documentUrl)

    let sourcekitdResponse = try await withTimeout(timeout) {
      let restartTimeoutHandle = TimeoutHandle()
      do {
        return try await withTimeout(restartTimeout, handle: restartTimeoutHandle) {
          await self.willSend(request: request)
          return try await withCancellableCheckedThrowingContinuation { (continuation) -> SourceKitDRequestHandle? in
            logger.info(
              """
              Sending sourcekitd request:
              \(request.forLogging)
              """
            )
            var handle: sourcekitd_api_request_handle_t? = nil
            self.api.send_request(request.dict, &handle) { response in
              continuation.resume(returning: SKDResponse(response!, sourcekitd: self))
            }
            Task {
              await self.didSend(request: request)
            }
            if let handle {
              return SourceKitDRequestHandle(handle: handle)
            }
            return nil
          } cancel: { (handle: SourceKitDRequestHandle?) in
            if let handle {
              logger.info(
                """
                Cancelling sourcekitd request:
                \(request.forLogging)
                """
              )
              self.api.cancel_request(handle.handle)
            }
          }
        }
      } catch let error as TimeoutError where error.handle == restartTimeoutHandle {
        if !self.path.lastPathComponent.contains("InProc") {
          logger.fault(
            "Did not receive reply from sourcekitd after \(restartTimeout, privacy: .public). Terminating and restarting sourcekitd."
          )
          await self.crash()
        } else {
          logger.fault(
            "Did not receive reply from sourcekitd after \(restartTimeout, privacy: .public). Not terminating sourcekitd because it is run in-process."
          )
        }
        throw error
      }
    }

    logger.log(
      level: (sourcekitdResponse.error == nil || sourcekitdResponse.error == .requestCancelled) ? .debug : .error,
      """
      Received sourcekitd response:
      \(sourcekitdResponse.forLogging)
      """
    )

    guard let dict = sourcekitdResponse.value else {
      if sourcekitdResponse.error == .connectionInterrupted {
        var log = """
          Request:
          \(request.description)

          File contents:
          \(fileContents ?? "<nil>")
          """

        if let documentUrl {
          let contextualRequests = (contextualRequests[documentUrl] ?? []).filter { $0.request !== request }
          for (index, contextualRequest) in contextualRequests.enumerated() {
            log += """

              Contextual request \(index + 1) / \(contextualRequests.count):
              \(contextualRequest.request.description)
              """
          }
        }
        let chunks = splitLongMultilineMessage(message: log)
        for (index, chunk) in chunks.enumerated() {
          logger.fault(
            """
            sourcekitd crashed (\(index + 1)/\(chunks.count))
            \(chunk)
            """
          )
        }
      }
      if sourcekitdResponse.error == .requestCancelled && !Task.isCancelled {
        throw SKDError.timedOut
      }
      throw sourcekitdResponse.error!
    }

    return dict
  }

  package func crash() async {
    _ = try? await send(
      \.crashWithExit,
      dictionary([:]),
      timeout: .seconds(60),
      restartTimeout: .seconds(24 * 60 * 60),
      documentUrl: nil,
      fileContents: nil
    )
  }
}

/// A sourcekitd notification handler in a class to allow it to be uniquely referenced.
package protocol SKDNotificationHandler: AnyObject, Sendable {
  func notification(_: SKDResponse)
}

struct WeakSKDNotificationHandler: Sendable {
  weak private(set) var value: (any SKDNotificationHandler)?
  init(_ value: any SKDNotificationHandler) {
    self.value = value
  }
}
