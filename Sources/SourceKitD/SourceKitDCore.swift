//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
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

/// A loaded sourcekitd dylib connection.
///
/// Owns the `DLHandle` and knows how to initialize the sourcekitd service and wire up the
/// one-shot C notification callback. The high-level API (`send`, UID accessors, plugin APIs)
/// lives in `SourceKitD`, which wraps `any SourceKitDCore`.
package protocol SourceKitDCore: Sendable {
  var dlHandle: DLHandle { get }
  var path: URL { get }

  /// Called once by `SourceKitD.init(core:)` after loading `sourcekitd_api_functions_t`.
  ///
  /// Owns-lifecycle implementations call `api.initialize()` and
  /// `api.set_notification_handler` here. Pre-initialized cores implement this as a no-op
  /// (or forward `notificationCallback` through their own notification mechanism).
  func initializeService(
    api: sourcekitd_api_functions_t,
    notificationCallback: @escaping @Sendable (sourcekitd_api_response_t) -> Void
  )
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

/// The standard `SourceKitDCore` implementation that opens a sourcekitd dylib directly.
///
/// Responsible only for dylib lifecycle: `dlopen`, `initialize`, `shutdown`, and wiring up the
/// single C notification callback. All `dlsym`-based API access lives in `SourceKitD`.
final class SourceKitDCoreImpl: SourceKitDCore, Sendable {
  let dlHandle: DLHandle
  let path: URL

  private let pluginPaths: PluginPaths?

  // Written once in `initializeService` (called during `SourceKitD.init`, before the instance
  // is shared) and read only in `deinit`, so no concurrent access is possible.
  private nonisolated(unsafe) var shutdown: (@convention(c) () -> Void)?
  private nonisolated(unsafe) var setNotificationHandler:
    (@convention(c) ((@Sendable (sourcekitd_api_response_t?) -> Void)?) -> Void)?

  init(dylib path: URL, pluginPaths: PluginPaths?) throws {
    #if os(Windows)
    let dlopenModes: DLOpenFlags = []
    #else
    let dlopenModes: DLOpenFlags = [.lazy, .local, .first]
    #endif
    let dlhandle = try dlopen(path.filePath, mode: dlopenModes)
    self.path = path
    self.dlHandle = dlhandle
    self.pluginPaths = pluginPaths
  }

  deinit {
    setNotificationHandler?(nil)
    shutdown?()
    Task.detached(priority: .background) { [dlHandle, path] in
      orLog("Closing dylib \(path)") { try dlHandle.close() }
    }
  }

  func initializeService(
    api: sourcekitd_api_functions_t,
    notificationCallback: @escaping @Sendable (sourcekitd_api_response_t) -> Void
  ) {
    self.shutdown = api.shutdown
    self.setNotificationHandler = api.set_notification_handler
    if let pluginPaths {
      api.register_plugin_path?(pluginPaths.clientPlugin.path, pluginPaths.servicePlugin.path)
    }
    api.initialize()
    api.set_notification_handler { rawResponse in
      guard let rawResponse else { return }
      notificationCallback(rawResponse)
    }
  }
}
