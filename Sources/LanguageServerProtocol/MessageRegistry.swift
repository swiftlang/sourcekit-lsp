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

public final class MessageRegistry {

  public static let lspProtocol: MessageRegistry =
    MessageRegistry(requests: builtinRequests, notifications: builtinNotifications)

  private let methodToRequest: [String: _RequestType.Type]
  private let methodToNotification: [String: NotificationType.Type]

  public init(requests: [_RequestType.Type], notifications: [NotificationType.Type]) {
    self.methodToRequest = Dictionary(uniqueKeysWithValues: requests.map { ($0.method, $0) })
    self.methodToNotification = Dictionary(uniqueKeysWithValues: notifications.map { ($0.method, $0) })
  }

  /// Returns the type of the message named `method`, or nil if it is unknown.
  public func requestType(for method: String) -> _RequestType.Type? {
    return methodToRequest[method]
  }

  /// Returns the type of the message named `method`, or nil if it is unknown.
  public func notificationType(for method: String) -> NotificationType.Type? {
    return methodToNotification[method]
  }

}
