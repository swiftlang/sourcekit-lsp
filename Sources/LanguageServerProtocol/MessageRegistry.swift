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

public final class MessageRegistry {

  private(set)
  var methodToRequest: [String: _RequestType.Type] = {
    Dictionary(uniqueKeysWithValues: builtinRequests.map { ($0.method, $0) })
  }()

  private(set)
  var methodToNotification: [String: NotificationType.Type] = {
    Dictionary(uniqueKeysWithValues: builtinNotifications.map { ($0.method, $0) })
  }()

  /// The global message registry.
  public static let shared: MessageRegistry = .init()

  /// Returns the type of the message named `method`, or nil if it is unknown.
  public func requestType(for method: String) -> _RequestType.Type? {
    return methodToRequest[method]
  }

  /// Returns the type of the message named `method`, or nil if it is unknown.
  public func notificationType(for method: String) -> NotificationType.Type? {
    return methodToNotification[method]
  }

  /// Adds a new message type to the registry. **For test messages only; not thread-safe!**.
  public func _register(_ type: _RequestType.Type) {
    precondition(methodToRequest[type.method] == nil)
    methodToRequest[type.method] = type
  }

  /// Adds a new message type to the registry. **For test messages only; not thread-safe!**.
  public func _register(_ type: NotificationType.Type) {
    precondition(methodToNotification[type.method] == nil)
    methodToNotification[type.method] = type
  }
}
