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

import SKSupport
import TSCBasic
import Foundation

/// Wrapper for sourcekitd, taking care of initialization, shutdown, and notification handler
/// multiplexing.
///
/// Users of this class should not call the api functions `initialize`, `shutdown`, or
/// `set_notification_handler`, which are global state managed internally by this class.
public final class SourceKitDImpl: SourceKitD {

  /// The path to the sourcekitd dylib.
  public let path: AbsolutePath

  /// The handle to the dylib.
  let dylib: DLHandle

  /// The sourcekitd API functions.
  public let api: sourcekitd_functions_t

  /// Convenience for accessing known keys.
  public let keys: sourcekitd_keys

  /// Convenience for accessing known keys.
  public let requests: sourcekitd_requests

  /// Convenience for accessing known keys.
  public let values: sourcekitd_values

  /// Lock protecting private state.
  let lock: Lock = Lock()

  /// List of notification handlers that will be called for each notification.
  private var _notificationHandlers: [WeakSKDNotificationHandler] = []

  var notificationHandlers: [SKDNotificationHandler] {
    lock.withLock {
      _notificationHandlers.compactMap { $0.value }
    }
  }

  public static func getOrCreate(dylibPath: AbsolutePath) throws -> SourceKitD {
    try SourceKitDRegistry.shared
      .getOrAdd(dylibPath, create: { try SourceKitDImpl(dylib: dylibPath) })
  }

  init(dylib path: AbsolutePath) throws {
    self.path = path
    #if os(Windows)
    self.dylib = try dlopen(path.pathString, mode: [])
    #else
    self.dylib = try dlopen(path.pathString, mode: [.lazy, .local, .first])
    #endif
    self.api = try sourcekitd_functions_t(self.dylib)
    self.keys = sourcekitd_keys(api: self.api)
    self.requests = sourcekitd_requests(api: self.api)
    self.values = sourcekitd_values(api: self.api)

    self.api.initialize()
    self.api.set_notification_handler { [weak self] rawResponse in
      guard let self = self else { return }
      let handlers = self.lock.withLock { self._notificationHandlers.compactMap(\.value) }

      let response = SKDResponse(rawResponse, sourcekitd: self)
      for handler in handlers {
        handler.notification(response)
      }
    }
  }

  deinit {
    self.api.set_notification_handler(nil)
    self.api.shutdown()
    // FIXME: is it safe to dlclose() sourcekitd? If so, do that here. For now, let the handle leak.
    dylib.leak()
  }

  /// Adds a new notification handler (referenced weakly).
  public func addNotificationHandler(_ handler: SKDNotificationHandler) {
    lock.withLock {
      _notificationHandlers.removeAll(where: { $0.value == nil })
      _notificationHandlers.append(.init(handler))
    }
  }

  /// Removes a previously registered notification handler.
  public func removeNotificationHandler(_ handler: SKDNotificationHandler) {
    lock.withLock {
      _notificationHandlers.removeAll(where: { $0.value == nil || $0.value === handler})
    }
  }
}

struct WeakSKDNotificationHandler {
  weak private(set) var value: SKDNotificationHandler?
  init(_ value: SKDNotificationHandler) {
    self.value = value
  }
}
