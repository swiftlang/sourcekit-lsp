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

#if compiler(>=6)
public import LanguageServerProtocol
#else
import LanguageServerProtocol
#endif

/// The log message notification is sent from a server to a client to ask the client to log a particular message in its console.
///
/// A `build/logMessage`` notification is similar to LSP's `window/logMessage``.
public struct OnBuildLogMessageNotification: NotificationType {
  public static let method: String = "build/logMessage"

  /// The message type.
  public var type: MessageType

  /// The actual message.
  public var message: String

  /// If specified, allows grouping log messages that belong to the same originating task together instead of logging
  /// them in chronological order in which they were produced.
  public var structure: StructuredLogKind?

  public init(type: MessageType, message: String, structure: StructuredLogKind?) {
    self.type = type
    self.message = message
    self.structure = structure
  }
}
