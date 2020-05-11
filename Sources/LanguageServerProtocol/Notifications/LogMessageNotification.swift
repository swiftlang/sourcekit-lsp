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

/// Notification from the server containing a log message.
///
/// - Parameters:
///   - type: The kind of log message.
///   - message: The contents of the message.
public struct LogMessageNotification: NotificationType, Hashable {
  public static let method: String = "window/logMessage"

  /// The kind of log message.
  public var type: WindowMessageType

  /// The contents of the message.
  public var message: String

  public init(type: WindowMessageType, message: String) {
    self.type = type
    self.message = message
  }
}
