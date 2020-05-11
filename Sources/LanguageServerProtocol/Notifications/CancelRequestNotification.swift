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

/// Notification that the given request (previously made) should be cancelled, if possible.
///
/// Cancellation is not guaranteed and the underlying request may finish normally. If the request is
/// successfully cancelled, it should return the `.cancelled` error code.
///
/// As with any `$` requests, the server is free to ignore this notification.
///
/// - Parameter id: The request to cancel.
public struct CancelRequestNotification: NotificationType, Hashable {
  public static let method: String = "$/cancelRequest"

  /// The request to cancel.
  public var id: RequestID

  public init(id: RequestID) {
    self.id = id
  }
}
