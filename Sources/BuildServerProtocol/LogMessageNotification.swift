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

public enum LogMessageType: Int, Sendable, Codable {
  /// An error message.
  case error = 1

  /// A warning message.
  case warning = 2

  /// An information message.
  case info = 3

  /// A log message.
  case log = 4
}

public typealias TaskIdentifier = String

public struct TaskId: Sendable, Codable {
  /// A unique identifier
  public var id: TaskIdentifier

  ///  The parent task ids, if any. A non-empty parents field means
  /// this task is a sub-task of every parent task id. The child-parent
  /// relationship of tasks makes it possible to render tasks in
  /// a tree-like user interface or inspect what caused a certain task
  /// execution.
  /// OriginId should not be included in the parents field, there is a separate
  /// field for that.
  public var parents: [TaskIdentifier]?

  public init(id: TaskIdentifier, parents: [TaskIdentifier]? = nil) {
    self.id = id
    self.parents = parents
  }
}

/// The log message notification is sent from a server to a client to ask the client to log a particular message in its console.
///
/// A `build/logMessage`` notification is similar to LSP's `window/logMessage``, except for a few additions like id and originId.
public struct LogMessageNotification: NotificationType {
  public static let method: String = "build/logMessage"

  /// The message type.
  public var type: LogMessageType

  /// The task id if any.
  public var task: TaskId?

  /// The actual message.
  public var message: String

  public init(type: LogMessageType, task: TaskId? = nil, message: String) {
    self.type = type
    self.task = task
    self.message = message
  }
}
