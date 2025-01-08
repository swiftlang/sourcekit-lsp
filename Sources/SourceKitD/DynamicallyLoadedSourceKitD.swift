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

#if compiler(>=6)
package import Csourcekitd
package import Foundation
import SKLogging
import SwiftExtensions
#else
import Csourcekitd
import Foundation
import SKLogging
import SwiftExtensions
#endif

extension sourcekitd_api_keys: @unchecked Sendable {}
extension sourcekitd_api_requests: @unchecked Sendable {}
extension sourcekitd_api_values: @unchecked Sendable {}

fileprivate extension ThreadSafeBox {
  /// If the wrapped value is `nil`, run `compute` and store the computed value. If it is not `nil`, return the stored
  /// value.
  func computeIfNil<WrappedValue>(compute: () -> WrappedValue) -> WrappedValue where T == Optional<WrappedValue> {
    return withLock { value in
      if let value {
        return value
      }
      let computed = compute()
      value = computed
      return computed
    }
  }
}

/// Wrapper for sourcekitd, taking care of initialization, shutdown, and notification handler
/// multiplexing.
///
/// Users of this class should not call the api functions `initialize`, `shutdown`, or
/// `set_notification_handler`, which are global state managed internally by this class.
package actor DynamicallyLoadedSourceKitD: SourceKitD {
  /// The path to the sourcekitd dylib.
  package let path: URL

  /// The handle to the dylib.
  let dylib: DLHandle

  /// The sourcekitd API functions.
  package let api: sourcekitd_api_functions_t

  private let pluginApiResult: Result<sourcekitd_plugin_api_functions_t, Error>
  package nonisolated var pluginApi: sourcekitd_plugin_api_functions_t { try! pluginApiResult.get() }

  private let servicePluginApiResult: Result<sourcekitd_service_plugin_api_functions_t, Error>
  package nonisolated var servicePluginApi: sourcekitd_service_plugin_api_functions_t {
    try! servicePluginApiResult.get()
  }

  private let ideApiResult: Result<sourcekitd_ide_api_functions_t, Error>
  package nonisolated var ideApi: sourcekitd_ide_api_functions_t { try! ideApiResult.get() }

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

  package static func getOrCreate(
    dylibPath: URL,
    pluginPaths: PluginPaths?
  ) async throws -> SourceKitD {
    try await SourceKitDRegistry.shared
      .getOrAdd(
        dylibPath,
        pluginPaths: pluginPaths,
        create: { try DynamicallyLoadedSourceKitD(dylib: dylibPath, pluginPaths: pluginPaths) }
      )
  }

  package init(dylib path: URL, pluginPaths: PluginPaths?, initialize: Bool = true) throws {
    #if os(Windows)
    let dlopenModes: DLOpenFlags = []
    #else
    let dlopenModes: DLOpenFlags = [.lazy, .local, .first]
    #endif
    let dlhandle = try dlopen(path.filePath, mode: dlopenModes)
    do {
      try self.init(
        dlhandle: dlhandle,
        path: path,
        pluginPaths: pluginPaths,
        initialize: initialize
      )
    } catch {
      try? dlhandle.close()
      throw error
    }
  }

  package init(dlhandle: DLHandle, path: URL, pluginPaths: PluginPaths?, initialize: Bool) throws {
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

    api.register_plugin_path?(pluginPaths?.clientPlugin.path, pluginPaths?.servicePlugin.path)
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
  }

  deinit {
    self.api.set_notification_handler(nil)
    self.api.shutdown()
    Task.detached(priority: .background) { [dylib, path] in
      orLog("Closing dylib \(path)") { try dylib.close() }
    }
  }

  /// Adds a new notification handler (referenced weakly).
  package func addNotificationHandler(_ handler: SKDNotificationHandler) {
    notificationHandlers.removeAll(where: { $0.value == nil })
    notificationHandlers.append(.init(handler))
  }

  /// Removes a previously registered notification handler.
  package func removeNotificationHandler(_ handler: SKDNotificationHandler) {
    notificationHandlers.removeAll(where: { $0.value == nil || $0.value === handler })
  }

  package nonisolated func log(request: SKDRequestDictionary) {
    logger.info(
      """
      Sending sourcekitd request:
      \(request.forLogging)
      """
    )
  }

  package nonisolated func log(response: SKDResponse) {
    logger.log(
      level: (response.error == nil || response.error == .requestCancelled) ? .debug : .error,
      """
      Received sourcekitd response:
      \(response.forLogging)
      """
    )
  }

  package nonisolated func log(crashedRequest req: SKDRequestDictionary, fileContents: String?) {
    let log = """
      Request:
      \(req.description)

      File contents:
      \(fileContents ?? "<nil>")
      """
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

  package nonisolated func logRequestCancellation(request: SKDRequestDictionary) {
    // We don't need to log which request has been cancelled because we can associate the cancellation log message with
    // the send message via the log
    logger.info(
      """
      Cancelling sourcekitd request:
      \(request.forLogging)
      """
    )
  }
}

struct WeakSKDNotificationHandler: Sendable {
  weak private(set) var value: SKDNotificationHandler?
  init(_ value: SKDNotificationHandler) {
    self.value = value
  }
}
