//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

/// The log message notification is sent from a server to a client to ask the client to log a particular message in its console.
///
/// A `build/logMessage`` notification is similar to LSP's `window/logMessage``, except for a few additions like id and originId.
public struct OnBuildLogMessageNotification: NotificationType {
  public static let method: String = "build/logMessage"

  /// The message type.
  public var type: MessageType

  /// The task id if any.
  public var task: TaskId?

  /// The actual message.
  public var message: String

  public init(type: MessageType, task: TaskId? = nil, message: String) {
    self.type = type
    self.task = task
    self.message = message
  }
}
