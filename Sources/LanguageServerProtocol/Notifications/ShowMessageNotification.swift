//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Notification from the server containing a message for the client to display.
///
/// - Parameters:
///   - type: The kind of message.
///   - message: The contents of the message.
public struct ShowMessageNotification: NotificationType, Hashable {
  public static let method: String = "window/showMessage"

  /// The kind of message.
  public var type: WindowMessageType

  /// The contents of the message.
  public var message: String

  public init(type: WindowMessageType, message: String) {
    self.type = type
    self.message = message
  }
}
